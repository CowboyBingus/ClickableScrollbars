-- Windows platform tests: FFI declarations, GDI capture and the sampler.
--
-- Runs outside the game (console LuaJIT), so a broken cdef, a wrong library or
-- a bad row stride fails the build instead of failing inside the game.

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

local options = module.parse_settings(nil, nil)
local sample = platform.capture(400, 400, options)
check('capture returns a sample', sample ~= nil)
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
