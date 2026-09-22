-- Windows platform tests: FFI declarations, GDI capture and the pixel sampler.

package.path = (arg and arg[1] or '.') .. '/?.lua;' .. package.path

rawset(_G, '__CLICKABLE_SCROLLBARS_TEST', true)
local module = assert(loadfile((arg and arg[2]) or 'ClickableScrollbars/src/clickable_scrollbars.lua'))()

local passed, failed = 0, 0
local function check(name, condition, detail)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print('FAIL ' .. name .. (detail and (' - ' .. tostring(detail)) or ''))
    end
end

local created, platform = pcall(module.create_platform)
check('create_platform succeeds', created, platform)
if not created then
    print(string.format('platform: %d passed, %d failed', passed, failed))
    os.exit(1)
end

check('cursor readable', type(platform.cursor()) == 'number' or platform.cursor() == nil)
check('foreground query', type(platform.foreground_self()) == 'boolean')
check('button query', type(platform.pressed()) == 'boolean')
check('key state query', type(platform.key_state()) == 'number')
check('display height readable', platform.display_height() == nil
    or (type(platform.display_height()) == 'number' and platform.display_height() >= 240),
    platform.display_height())

-- Lint for the v2.2 crash: a scratch buffer declared after its users is a global.
local function blank_non_code(text)
    -- Blank comments and the ffi.cdef string, keeping offsets stable so
    -- positions still compare. Parameter names inside the cdef block are not
    -- code and must not count as uses.
    text = text:gsub('%-%-[^\n]*', function(comment) return string.rep(' ', #comment) end)
    return (text:gsub('ffi%.cdef%s*%[%[.-%]%]', function(block) return string.rep(' ', #block) end))
end

local source_path = (arg and arg[2]) or 'ClickableScrollbars/src/clickable_scrollbars.lua'
local handle = assert(io.open(source_path, 'rb'))
local raw_text = handle:read('*a')
handle:close()
-- Locate the section on the raw text (the closing marker is itself a comment),
-- then lint the comment-free copy so a mention inside a comment cannot count.
local first = raw_text:find('function module%.create_platform')
local last = raw_text:find('%-%- %-+ install')
local source_text = blank_non_code(raw_text)
check('platform section located for the buffer lint', first ~= nil and last ~= nil)
if first and last then
    local section = source_text:sub(first, last)
    local buffers, offenders = 0, 0
    -- Every local initialised from ffi.new counts, including the multi-name form
    -- `local rect, client_origin = ffi.new(...), ffi.new(...)` that carried the
    -- shipped bug.
    for position, line in section:gmatch('()([^\n]*ffi%.new[^\n]*)') do
        local names = line:match('^%s*local%s+([%a_][%w_,%s]*)%s*=')
        if names then
            for name in names:gmatch('[%a_][%w_]*') do
                buffers = buffers + 1
                local pattern = '%f[%a_]' .. name .. '%f[^%a%d_]'
                local search, first_use = 1, nil
                while true do
                    local found = section:find(pattern, search)
                    if not found then break end
                    if found < position then first_use = first_use or found end
                    search = found + 1
                end
                if first_use then
                    offenders = offenders + 1
                    check(name .. ' buffer is declared before every use', false,
                        'first use at offset ' .. first_use .. ', declared at ' .. position)
                end
            end
        end
    end
    check('platform buffers were linted', buffers >= 5, buffers)
    check('no buffer is used before its declaration', offenders == 0, offenders)
end

local options = module.parse_settings(nil, nil)
local skip_capture = arg and arg[3] == '--skip-capture'
local sample
if skip_capture then
    print('SKIP desktop capture: interactive Windows desktop unavailable; not verified')
else
    sample = platform.capture(400, 400, options)
    check('capture returns a sample', sample ~= nil)
end
if sample then
    check('capture width matches', sample.width == math.min(options.strip_width, sample.width),
        sample.width)
    check('capture height is bounded', sample.height > 0 and sample.height <= options.window * 2 + 2,
        sample.height)
    check('capture stride is a row multiple', sample.stride % 4 == 0 and sample.stride >= sample.width * 4,
        sample.stride)
    local luminance = module.strip_luminance(sample)
    check('strip luminance readable', luminance ~= nil and luminance >= 0 and luminance <= 255, luminance)
    local action, reason = module.analyse(sample, {x = 0, y = 0}, options)
    check('analysis returns a decision', action ~= nil or type(reason) == 'string', reason)
end

platform.close()
check('close is idempotent', pcall(platform.close))

print(string.format('platform: %d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
