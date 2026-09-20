-- HD2-Addon: mods/cowboybingus/clickable_scrollbars
--
-- Click-to-scroll for the item-select menus.
--
-- The Armory, Loadout and mission-briefing lists draw their scrollbars in the
-- game's native UI, so the shipped XAML scrollbar templates cannot reach them
-- (a data override was verified ineffective in-game on 2026-09-20). Their bars
-- are still plain vertical thumbs: a uniform grey bar, roughly 9-14 px wide,
-- with dark panel background above and below it. This addon watches the left
-- mouse button, recognises that thumb from the rendered frame under the
-- cursor, and turns a click on the invisible track into mouse-wheel input -
-- which is the scroll path the game already implements.
--
-- Behaviour:
--   * press on the visible thumb -> grab it; the thumb then follows the
--     pointer one-to-one, so it moves exactly as far as the hand does
--   * press on the invisible track -> the thumb glides until its centre sits
--     under the pointer: one burst of wheel notches, then at most
--     max_corrections settle corrections that each shrink the error
--   * press elsewhere -> nothing
--
-- Two rules keep the motion honest. First, input is only ever produced by the
-- pointer, never by a timer: every notch a click or a drag asks for is sent on
-- the frame that asked for it, so the bar cannot run on after the pointer
-- stops and cannot fall behind while it moves (a paced queue caused both).
-- Second, a settle correction only runs when the thumb has stopped moving,
-- and only when the predicted step is smaller than the error it removes, so a
-- correction can never overshoot into a visible back-and-forth.
--
-- pixels_per_notch starts at default_pixels_per_notch and is re-learned as the
-- median of the last calibration_samples observed thumb displacements, so both
-- the jump and the drag use the step this machine actually produces.
--
-- Everything the addon decides is written to
-- %LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ClickableScrollbars.log
-- (shared loader folder): the settings in force, counters, timing health, the
-- tracked thumb, the calibration samples, a tally of every decision reason and
-- the last trace_lines decisions with millisecond stamps. An optional
-- %LOCALAPPDATA%/ClickableScrollbars/ClickableScrollbars.ini can override the
-- settings below. With dump_captures=0 (the default) no images are written, so
-- the log is the only file this addon touches.
--
-- Requires Bingus Shared Loader API 1 (v15+ discovers this entry).
--
-- Loader-only guarantee: this addon is a plaintext Lua resource loaded by the
-- mod loader. It ships no DLL, patches no executable code, writes no game
-- memory, installs no system hooks and touches no game file. It reads pixels
-- (GDI BitBlt), polls the left button (GetAsyncKeyState) and injects wheel
-- events (SendInput) from inside the running game, nothing else. The build
-- refuses to package a script that uses those APIs.

local module = {revision = 'v2.1'}

local DEFAULTS = {
    enabled = true,
    -- Capture geometry.
    strip_width = 96,        -- px captured horizontally, centred on the cursor
    window = 460,            -- px captured vertically either side of the cursor
    narrow_width = 40,       -- px wide second pass once a bar column is known
    narrow_window = 420,     -- px tall second pass
    bar_cache_ms = 60000,    -- how long a known bar column is trusted
    -- Thumb classification.
    min_height = 44,         -- shortest accepted thumb, px
    max_height_ratio = 0.94, -- longest accepted thumb, fraction of the capture
    min_width = 6,           -- narrowest accepted thumb, px
    max_width = 28,          -- widest accepted thumb, px
    min_luma = 105,          -- thumb brightness window
    max_luma = 220,
    min_luma_floor = 40,     -- absolute floor once the threshold is adapted
    min_contrast = 30,       -- thumb must be this much brighter than the strip's dark quartile
    local_contrast = true,   -- and brighter than the pixels beside it (rejects wide bright areas)
    local_offset = 16,       -- px to either side used for that comparison
    max_spread = 18,         -- max channel spread for "neutral grey"
    min_fill = 0.72,         -- fraction of grey pixels required inside a run
    max_bridge = 160,        -- masked rows a run may bridge (cursor overlay)
    max_gap = 6,             -- unmasked rows a run may bridge (small bright overlay)
    max_variance = 14,       -- max deviation from the thumb's median brightness
    min_uniformity = 0.85,   -- fraction of samples that must stay within it
    edge_contrast = 25,      -- background beside the thumb must be this much darker
    -- Click interpretation.
    thumb_margin = 9,        -- px around the thumb treated as the thumb
    column_tolerance = 12,   -- px the cursor may sit outside the thumb column
    click_contrast = 25,     -- click pixel must be this much darker than the bar
    -- Bounding box of the pointer's sprite. Live captures show a coloured blob
    -- about 100 px across (channel spread up to 91 luma) with a bright core,
    -- plus a mild neutral halo (+20..45 luma) that reaches further out. Inside
    -- this box a row that is coloured or too bright to judge is bridged rather
    -- than read as background, so the thumb stays whole under the pointer; the
    -- halo outside it is handled by the luma window and the local-contrast
    -- test, because a smooth lift has no contrast against its own neighbours.
    cursor_mask = {x0 = -72, x1 = 72, y0 = -72, y1 = 72},
    -- Aiming and following.
    default_pixels_per_notch = 13, -- measured wheel step before calibration
    center_tolerance = 4,    -- px of aimed error that counts as centred
    jump_max_notches = 120,  -- notches one track-click jump may send
    correction_notches = 40, -- notches one settle correction may add
    max_corrections = 2,     -- settle corrections per jump, each of which must shrink the error
    settle_delay_ms = 200,   -- wait after a jump before measuring the thumb
    settle_interval_ms = 60, -- between settle measurements
    settle_stable_px = 2,    -- movement below this counts as stopped
    settle_checks = 8,       -- measurements before a jump is given up
    drag_threshold = 10,     -- px of vertical movement that starts a drag
    drag_max_step_px = 220,  -- a larger single-frame jump is a pointer teleport
    drag_max_notches = 40,   -- hard cap on the notches one drag frame may send
    calibration_samples = 7, -- observed steps kept for the median
    calibration_min_px = 4,  -- accepted observed px/notch window
    calibration_max_px = 60,
    -- Diagnostics.
    trace_lines = 48,        -- decisions kept for the log
    trace_events = 0,        -- 1 records every emission and drag step
    log_interval_ms = 1000,  -- shortest gap between log writes
    cooldown_ms = 0,         -- shortest gap between two track-click jumps
    min_capture_interval_ms = 40,
    use_window_capture = 1,  -- 1 tries the game's own window DC before the desktop DC
    error_limit = 8,         -- frame errors tolerated before the addon stops
    dump_captures = 0,       -- diagnostic BMP dumps; 0 keeps nothing on disk
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function luminance(r, g, b)
    return (r * 299 + g * 587 + b * 114) / 1000
end

-- ---------------------------------------------------------------- detection

-- A capture sample exposes width, height, origin_x, origin_y and
-- rgb(x, y) -> r, g, b for strip-local coordinates.

function module.thumb_pixel(sample, x, y, options)
    local r, g, b = sample.rgb(x, y)
    if r == nil then return nil end
    local high, low = r, r
    if g > high then high = g end
    if b > high then high = b end
    if g < low then low = g end
    if b < low then low = b end
    if high - low > options.max_spread then return nil end
    local value = luminance(r, g, b)
    if value < options.min_luma or value > options.max_luma then return nil end
    return value
end

local function raw_luma(sample, x, y)
    local r, g, b = sample.rgb(x, y)
    if r == nil then return nil end
    return luminance(r, g, b)
end

-- True when a pixel can be read as track: neutral, and darker than the thumb
-- window. A pixel that is neither track nor a thumb pixel (coloured, or
-- brighter than the accepted window) is unjudgeable rather than background.
function module.track_pixel(sample, x, y, options)
    local r, g, b = sample.rgb(x, y)
    if r == nil then return false end
    local high, low = r, r
    if g > high then high = g end
    if b > high then high = b end
    if g < low then low = g end
    if b < low then low = b end
    if high - low > options.max_spread then return false end
    return luminance(r, g, b) < options.min_luma
end

-- Coarse brightness of a capture, used to detect a black frame (a GDI capture
-- that never sees the rendered game, e.g. under an overlay plane).
function module.strip_luminance(sample)
    local step_x = math.max(1, math.floor(sample.width / 24))
    local step_y = math.max(1, math.floor(sample.height / 24))
    local total, count = 0, 0
    for y = 0, sample.height - 1, step_y do
        for x = 0, sample.width - 1, step_x do
            local value = raw_luma(sample, x, y)
            if value then
                total = total + value
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return total / count
end

-- Dark-quartile luminance of a capture, used to place the thumb threshold
-- relative to the frame the game actually produced. Bright menus are ignored
-- by taking a low quantile instead of the mean.
function module.background_luminance(sample, quantile)
    local step_x = math.max(1, math.floor(sample.width / 32))
    local step_y = math.max(1, math.floor(sample.height / 32))
    local histogram, total = {}, 0
    for y = 0, sample.height - 1, step_y do
        for x = 0, sample.width - 1, step_x do
            local value = raw_luma(sample, x, y)
            if value then
                local bucket = math.floor(value / 8)
                histogram[bucket] = (histogram[bucket] or 0) + 1
                total = total + 1
            end
        end
    end
    if total == 0 then return nil end
    local target = math.max(1, math.floor(total * (quantile or 0.25)))
    local seen = 0
    for bucket = 0, 31 do
        seen = seen + (histogram[bucket] or 0)
        if seen >= target then return bucket * 8 + 4 end
    end
    return 255
end

-- Per-capture copy of the settings with the thumb brightness window adapted to
-- the measured background, so a dim GDI capture of an HDR frame behaves like
-- the bright reference screenshots.
function module.adapt_options(sample, options)
    local background = module.background_luminance(sample)
    if background == nil then return options, nil end
    local tuned = {}
    for key, value in pairs(options) do tuned[key] = value end
    tuned.min_luma = math.max(options.min_luma_floor or 40, background + (options.min_contrast or 30))
    if tuned.min_luma > 240 then tuned.min_luma = 240 end
    return tuned, background
end

local function cursor_masked(cursor, mask, x, y)
    if not cursor then return false end
    return x >= cursor.x + mask.x0 and x <= cursor.x + mask.x1
        and y >= cursor.y + mask.y0 and y <= cursor.y + mask.y1
end

-- Longest vertical grey run per column, bridging rows hidden by the cursor.
local function column_runs(sample, cursor, options)
    local columns = {}
    for x = 0, sample.width - 1 do
        local runs, start, grey, filled, bridge, gap, last_grey = {}, nil, 0, 0, 0, 0, nil
        local run_masked = false
        local function close(ending)
            if not start then return end
            -- Masked or interrupted rows only count as part of the thumb when
            -- another thumb pixel follows them.
            filled = filled - gap
            ending = math.min(ending, (last_grey or start) + 1)
            local length = ending - start
            if length >= options.min_height and length <= sample.height * options.max_height_ratio
                and grey >= filled * options.min_fill then
                -- A run that starts or ends against the cursor mask has been
                -- clipped by the glow on that side; its hidden part must be
                -- inferred from the tracked thumb height.
                local clipped_top = cursor_masked(cursor, options.cursor_mask, x, start - 1)
                local clipped_bottom = cursor_masked(cursor, options.cursor_mask, x, ending)
                runs[#runs + 1] = {top = start, bottom = ending - 1,
                                   clipped_top = clipped_top and true or false,
                                   clipped_bottom = clipped_bottom and true or false,
                                   -- Only a clipped end makes the extent
                                   -- untrustworthy; a hidden middle does not.
                                   masked = (clipped_top or clipped_bottom) and true or false}
            end
            start, grey, filled, bridge, gap, last_grey = nil, 0, 0, 0, 0, nil
            run_masked = false
        end
        for y = 0, sample.height - 1 do
            local covered = cursor_masked(cursor, options.cursor_mask, x, y)
            local value = covered and nil or module.thumb_pixel(sample, x, y, options)
            if value and options.local_contrast then
                -- Wide bright areas (panels, blurred background) must not
                -- look like a thumb: require clearly darker pixels beside
                -- the column at the same row.
                local offset = options.local_offset or 16
                local left, right = raw_luma(sample, x - offset, y), raw_luma(sample, x + offset, y)
                if not left and not right then
                    value = nil
                else
                    local beside = ((left or right) + (right or left)) / 2
                    if value - beside < options.min_contrast then value = nil end
                end
            end
            if not value and covered and not module.track_pixel(sample, x, y, options) then
                -- The pointer's own sprite covers this row and its pixels are
                -- coloured or too bright to judge: it is hidden, not missing,
                -- so a run keeps going through it. A row that reads as track
                -- still ends the run, because the panel is visible there.
                if start then
                    bridge = bridge + 1
                    run_masked = true
                    if bridge > options.max_bridge then
                        start, grey, filled, bridge, gap, last_grey = nil, 0, 0, 0, 0, nil
                        run_masked = false
                    end
                end
            else
                bridge = 0
                if value then
                    if not start then start, grey, filled, gap = y, 0, 0, 0 end
                    grey, filled, gap, last_grey = grey + 1, filled + 1, 0, y
                elseif start then
                    gap = gap + 1
                    filled = filled + 1
                    if gap > options.max_gap then close(y - gap + 1) end
                end
            end
        end
        close(sample.height)
        if #runs > 0 then columns[x] = runs end
    end
    return columns
end

local function overlaps(first, second)
    local top = math.max(first.top, second.top)
    local bottom = math.min(first.bottom, second.bottom)
    if bottom < top then return false end
    local shortest = math.min(first.bottom - first.top, second.bottom - second.top)
    if shortest <= 0 then return false end
    return (bottom - top) >= shortest * 0.6
end

-- A thumb is uniform along its length and clearly darker-edged on both sides.
-- Rows hidden by the cursor's glow are skipped rather than judged.
local function bar_quality(sample, bar, options, cursor)
    local height = bar.bottom - bar.top + 1
    local middle = math.floor((bar.left + bar.right) / 2)
    local values, count = {}, 0
    for y = bar.top, bar.bottom, 3 do
        local value = nil
        if not cursor_masked(cursor, options.cursor_mask, middle, y) then
            value = module.thumb_pixel(sample, middle, y, options)
        end
        if value then
            count = count + 1
            values[#values + 1] = value
        end
    end
    if count < 4 then return false, 'sparse' end
    table.sort(values)
    local median = values[math.floor((count + 1) / 2)]
    local near = 0
    for index = 1, #values do
        if math.abs(values[index] - median) <= options.max_variance then near = near + 1 end
    end
    if near < count * options.min_uniformity then return false, 'not_uniform' end
    local best = nil
    for y = bar.top + 4, bar.bottom - 4, 7 do
        if not cursor_masked(cursor, options.cursor_mask, middle, y) then
            local outside, sides = 0, 0
            for _, range in ipairs({{bar.left - 3, bar.left - 1}, {bar.right + 1, bar.right + 3}}) do
                local total, samples = 0, 0
                for x = range[1], range[2] do
                    local value = raw_luma(sample, x, y)
                    if value then
                        total = total + value
                        samples = samples + 1
                    end
                end
                if samples > 0 then
                    outside = outside + total / samples
                    sides = sides + 1
                end
            end
            if sides > 0 then
                local value = outside / sides
                if not best or value < best then best = value end
            end
        end
    end
    if best and best > median - options.edge_contrast then
        return false, 'no_edge'
    end
    return true, median, height
end

-- Merge per-column runs into candidate bars. `band`, when given, selects the
-- bar overlapping those strip-local x coordinates instead of the cursor.
function module.find_thumb(sample, cursor, options, band)
    local columns = column_runs(sample, cursor, options)
    local bars, current = {}, nil
    for x = 0, sample.width - 1 do
        local runs = columns[x]
        local best = nil
        if runs then
            -- The cursor glow can split one thumb into two runs inside the same
            -- column; when both parts face the gap, they are one bar.
            local merged = {}
            for index = 1, #runs do
                local run = runs[index]
                local previous = merged[#merged]
                if previous and previous.clipped_bottom and run.clipped_top
                    and (run.top - previous.bottom) <= options.max_bridge then
                    previous.bottom = run.bottom
                    previous.clipped_bottom = run.clipped_bottom
                    previous.masked = previous.clipped_top or previous.clipped_bottom
                else
                    merged[#merged + 1] = {top = run.top, bottom = run.bottom,
                                           clipped_top = run.clipped_top,
                                           clipped_bottom = run.clipped_bottom,
                                           masked = run.masked}
                end
            end
            for index = 1, #merged do
                local run = merged[index]
                if not best or (run.bottom - run.top) > (best.bottom - best.top) then best = run end
            end
        end
        if best then
            if current and current.right == x - 1 and overlaps(current, best) then
                current.right = x
                if best.masked then current.masked = true end
                if best.clipped_top then current.clipped_top = true end
                if best.clipped_bottom then current.clipped_bottom = true end
                if best.top < current.top then current.top = best.top end
                if best.bottom > current.bottom then current.bottom = best.bottom end
            else
                if current then bars[#bars + 1] = current end
                current = {left = x, right = x, top = best.top, bottom = best.bottom,
                           masked = best.masked or false,
                           clipped_top = best.clipped_top or false,
                           clipped_bottom = best.clipped_bottom or false}
            end
        elseif current then
            bars[#bars + 1] = current
            current = nil
        end
    end
    if current then bars[#bars + 1] = current end

    local chosen, chosen_distance = nil, nil
    for index = 1, #bars do
        local bar = bars[index]
        local width = bar.right - bar.left + 1
        local height = bar.bottom - bar.top + 1
        if width >= options.min_width and width <= options.max_width and height >= options.min_height then
            local good, median = bar_quality(sample, bar, options, cursor)
            if good then bar.median = median end
            if not good then bar = nil end
        else
            bar = nil
        end
        if bar then
            if band then
                local overlap = math.min(bar.right, band.right) - math.max(bar.left, band.left) + 1
                if overlap > 0 then
                    local distance = -overlap
                    if not chosen or distance < chosen_distance then
                        chosen, chosen_distance = bar, distance
                    end
                end
            else
                local gap = 0
                if cursor.x < bar.left then gap = bar.left - cursor.x
                elseif cursor.x > bar.right then gap = cursor.x - bar.right end
                if gap <= options.column_tolerance then
                    local distance = gap * 4 + math.abs(cursor.y - clamp(cursor.y, bar.top, bar.bottom))
                    if not chosen or distance < chosen_distance then
                        chosen, chosen_distance = bar, distance
                    end
                end
            end
        end
    end
    if not chosen then return nil, 'no_thumb', bars end
    return chosen, nil, bars
end

-- Returns 'thumb' when the press landed on the visible bar, 'track' when it
-- landed on the invisible track beside it, or nil when it landed on list
-- content (bright pixels beside the bar). The direction is derived from the
-- tracked thumb position by the caller, not from where inside the bar the
-- press landed.
function module.decide(bar, cursor, sample, options)
    if cursor.y >= bar.top - options.thumb_margin and cursor.y <= bar.bottom + options.thumb_margin then
        return 'thumb', 'thumb'
    end
    local r, g, b = sample.rgb(cursor.x, cursor.y)
    if r ~= nil then
        local value = luminance(r, g, b)
        local bar_value = module.thumb_pixel(sample, bar.left + math.floor((bar.right - bar.left) / 2),
                                             bar.top + 2, options)
            or options.min_luma
        if value > bar_value - options.click_contrast then
            return nil, 'click_not_on_track'
        end
    end
    return 'track', 'track'
end

function module.analyse(sample, cursor, options, band)
    options, sample.background = module.adapt_options(sample, options)
    local bar, reason = module.find_thumb(sample, cursor, options, band)
    if not bar then return nil, reason end
    local hit, why = module.decide(bar, cursor, sample, options)
    if not hit then return nil, why, bar end
    return {bar = bar, hit = hit}, why
end

-- --------------------------------------------------------------- settings

function module.parse_settings(text, base)
    local settings = {}
    for key, value in pairs(base or DEFAULTS) do settings[key] = value end
    if type(text) == 'string' then
        for line in text:gmatch('[^\r\n]+') do
            local key, value = line:match('^%s*([%a_]+)%s*=%s*([%-%d%.]+)%s*$')
            if key and DEFAULTS[key] ~= nil and type(DEFAULTS[key]) ~= 'table' then
                local number = tonumber(value)
                if number then
                    if type(DEFAULTS[key]) == 'boolean' then
                        settings[key] = number ~= 0
                    else
                        settings[key] = number
                    end
                end
            end
        end
    end
    settings.strip_width = clamp(math.floor(settings.strip_width), 32, 240)
    settings.window = clamp(math.floor(settings.window), 120, 1400)
    settings.narrow_width = clamp(math.floor(settings.narrow_width), 16, 120)
    settings.narrow_window = clamp(math.floor(settings.narrow_window), 120, 1400)
    settings.bar_cache_ms = clamp(math.floor(settings.bar_cache_ms), 0, 600000)
    settings.min_height = clamp(math.floor(settings.min_height), 12, 1200)
    settings.max_height_ratio = clamp(settings.max_height_ratio, 0.1, 1)
    settings.min_width = clamp(math.floor(settings.min_width), 3, 60)
    settings.max_width = clamp(math.floor(settings.max_width), settings.min_width, 80)
    settings.min_luma = clamp(math.floor(settings.min_luma), 30, 250)
    settings.max_luma = clamp(math.floor(settings.max_luma), settings.min_luma + 5, 255)
    settings.min_luma_floor = clamp(math.floor(settings.min_luma_floor), 10, 240)
    settings.min_contrast = clamp(math.floor(settings.min_contrast), 5, 200)
    settings.local_contrast = settings.local_contrast and true or false
    settings.local_offset = clamp(math.floor(settings.local_offset), 4, 200)
    settings.max_spread = clamp(math.floor(settings.max_spread), 2, 120)
    settings.min_fill = clamp(settings.min_fill, 0.2, 1)
    settings.max_bridge = clamp(math.floor(settings.max_bridge), 0, 400)
    settings.max_gap = clamp(math.floor(settings.max_gap), 0, 400)
    settings.max_variance = clamp(math.floor(settings.max_variance), 1, 120)
    settings.min_uniformity = clamp(settings.min_uniformity, 0.1, 1)
    settings.edge_contrast = clamp(math.floor(settings.edge_contrast), 0, 200)
    settings.thumb_margin = clamp(math.floor(settings.thumb_margin), 0, 200)
    settings.column_tolerance = clamp(math.floor(settings.column_tolerance), 0, 120)
    settings.click_contrast = clamp(math.floor(settings.click_contrast), 0, 200)
    settings.default_pixels_per_notch = clamp(settings.default_pixels_per_notch, 4, 400)
    settings.center_tolerance = clamp(math.floor(settings.center_tolerance), 0, 100)
    settings.jump_max_notches = clamp(math.floor(settings.jump_max_notches), 1, 2000)
    settings.correction_notches = clamp(math.floor(settings.correction_notches), 1, 200)
    settings.max_corrections = clamp(math.floor(settings.max_corrections), 0, 30)
    settings.settle_delay_ms = clamp(math.floor(settings.settle_delay_ms), 20, 5000)
    settings.settle_interval_ms = clamp(math.floor(settings.settle_interval_ms), 10, 2000)
    settings.settle_stable_px = clamp(settings.settle_stable_px, 0, 100)
    settings.settle_checks = clamp(math.floor(settings.settle_checks), 1, 50)
    settings.drag_threshold = clamp(math.floor(settings.drag_threshold), 2, 200)
    settings.drag_max_step_px = clamp(math.floor(settings.drag_max_step_px), 20, 2000)
    settings.drag_max_notches = clamp(math.floor(settings.drag_max_notches), 1, 400)
    settings.calibration_samples = clamp(math.floor(settings.calibration_samples), 1, 25)
    settings.calibration_min_px = clamp(settings.calibration_min_px, 1, 200)
    settings.calibration_max_px = clamp(settings.calibration_max_px, settings.calibration_min_px, 400)
    settings.trace_lines = clamp(math.floor(settings.trace_lines), 0, 500)
    settings.trace_events = clamp(math.floor(settings.trace_events), 0, 1)
    settings.log_interval_ms = clamp(math.floor(settings.log_interval_ms), 0, 60000)
    settings.cooldown_ms = clamp(math.floor(settings.cooldown_ms), 0, 5000)
    settings.min_capture_interval_ms = clamp(math.floor(settings.min_capture_interval_ms), 0, 5000)
    settings.use_window_capture = clamp(math.floor(settings.use_window_capture), 0, 1)
    settings.error_limit = clamp(math.floor(settings.error_limit), 1, 1000)
    settings.dump_captures = clamp(math.floor(settings.dump_captures), 0, 50)
    settings.enabled = settings.enabled and true or false
    return settings
end

-- --------------------------------------------------------------- platform

function module.create_platform()
    local ffi = require('ffi')
    local bit = require('bit')
    assert(ffi.abi('64bit'), 'Windows x64 is required')
    ffi.cdef [[
        typedef struct { int x; int y; } HD2CS_POINT;
        typedef struct { int left; int top; int right; int bottom; } HD2CS_RECT;
        typedef struct {
            unsigned int biSize; int biWidth; int biHeight; unsigned short biPlanes;
            unsigned short biBitCount; unsigned int biCompression; unsigned int biSizeImage;
            int biXPelsPerMeter; int biYPelsPerMeter; unsigned int biClrUsed; unsigned int biClrImportant;
        } HD2CS_BITMAPINFOHEADER;
        typedef struct { HD2CS_BITMAPINFOHEADER bmiHeader; unsigned int bmiColors[3]; } HD2CS_BITMAPINFO;
        typedef struct {
            int dx; int dy; unsigned int mouseData; unsigned int dwFlags;
            unsigned int time; unsigned long long dwExtraInfo;
        } HD2CS_MOUSEINPUT;
        typedef struct { unsigned int type; unsigned int padding; HD2CS_MOUSEINPUT mi; } HD2CS_INPUT;
        int GetCursorPos(HD2CS_POINT *point);
        short GetAsyncKeyState(int key);
        void *GetForegroundWindow(void);
        void *GetDC(void *window);
        int ReleaseDC(void *window, void *dc);
        int GetSystemMetrics(int index);
        unsigned int GetCurrentProcessId(void);
        unsigned int GetWindowThreadProcessId(void *window, unsigned int *process);
        int GetClientRect(void *window, HD2CS_RECT *rect);
        int ClientToScreen(void *window, HD2CS_POINT *point);
        int IsWindow(void *window);
        unsigned int SendInput(unsigned int count, HD2CS_INPUT *inputs, int size);
        void *CreateCompatibleDC(void *dc);
        void *CreateDIBSection(void *dc, HD2CS_BITMAPINFO *info, unsigned int usage,
                               void **bits, void *section, unsigned int offset);
        void *SelectObject(void *dc, void *object);
        int BitBlt(void *dest, int x, int y, int width, int height, void *source,
                   int source_x, int source_y, unsigned int rop);
        int DeleteObject(void *object);
        int DeleteDC(void *dc);
        unsigned long long GetTickCount64(void);
    ]]
    local user32, gdi32, kernel32 = ffi.load('user32'), ffi.load('gdi32'), ffi.load('kernel32')

    -- LuaJIT resolves each imported symbol on first use, so every binding is
    -- exercised once here: a wrong library or a missing export must surface as
    -- a named startup error instead of failing on the first click.
    local function check(name, fn, ...)
        local ok, value = pcall(fn, ...)
        if not ok then error(name .. ': ' .. tostring(value), 0) end
        return value
    end
    check('GetTickCount64', function() return kernel32.GetTickCount64() end)
    local process_id = check('GetCurrentProcessId', function() return kernel32.GetCurrentProcessId() end)
    check('GetAsyncKeyState', function() return user32.GetAsyncKeyState(0) end)
    check('GetForegroundWindow', function() return user32.GetForegroundWindow() end)
    check('GetSystemMetrics', function() return user32.GetSystemMetrics(0) end)
    -- Indexing a loaded library resolves the symbol, so a missing export still
    -- surfaces at startup - without calling it with a null window handle.
    for _, name in ipairs({'IsWindow', 'GetClientRect', 'ClientToScreen'}) do
        if user32[name] == nil then error('user32.' .. name .. ' unavailable', 0) end
    end
    local screen_dc = check('GetDC', function() return user32.GetDC(nil) end)
    assert(screen_dc ~= nil, 'Screen device context unavailable')
    local memory_dc = check('CreateCompatibleDC', function() return gdi32.CreateCompatibleDC(screen_dc) end)
    assert(memory_dc ~= nil, 'Memory device context unavailable')
    local SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN = 76, 77
    local SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN = 78, 79
    local virtual = {
        x = user32.GetSystemMetrics(SM_XVIRTUALSCREEN),
        y = user32.GetSystemMetrics(SM_YVIRTUALSCREEN),
        width = user32.GetSystemMetrics(SM_CXVIRTUALSCREEN),
        height = user32.GetSystemMetrics(SM_CYVIRTUALSCREEN),
    }
    local dib_width = 240
    local dib_height = clamp(virtual.height, 480, 4320)
    local info = ffi.new('HD2CS_BITMAPINFO')
    info.bmiHeader.biSize = ffi.sizeof('HD2CS_BITMAPINFOHEADER')
    info.bmiHeader.biWidth = dib_width
    info.bmiHeader.biHeight = -dib_height -- top-down rows
    info.bmiHeader.biPlanes = 1
    info.bmiHeader.biBitCount = 32
    info.bmiHeader.biCompression = 0
    local bits = ffi.new('void *[1]')
    local bitmap = check('CreateDIBSection', function()
        return gdi32.CreateDIBSection(screen_dc, info, 0, bits, nil, 0)
    end)
    assert(bitmap ~= nil and bits[0] ~= nil, 'Capture bitmap unavailable')
    check('SelectObject', function() return gdi32.SelectObject(memory_dc, bitmap) end)
    local pixels = ffi.cast('unsigned char *', bits[0])
    local point = ffi.new('HD2CS_POINT[1]')
    local input = ffi.new('HD2CS_INPUT[1]')
    local input_size = ffi.sizeof('HD2CS_INPUT')
    input[0].type = 0
    input[0].mi.dwFlags = 0x0800 -- MOUSEEVENTF_WHEEL

    local platform = {}

    check('GetCursorPos', function() return user32.GetCursorPos(point) end)

    function platform.now()
        return tonumber(kernel32.GetTickCount64())
    end

    function platform.cursor()
        if user32.GetCursorPos(point) == 0 then return nil end
        return point[0].x, point[0].y
    end

    function platform.pressed()
        return bit.band(user32.GetAsyncKeyState(0x01), 0x8000) ~= 0
    end

    -- Raw two-byte GetAsyncKeyState value for VK_LBUTTON, for diagnostics
    -- (0x8000 = down now, 0x0001 = pressed since the previous query).
    function platform.key_state()
        local value = user32.GetAsyncKeyState(0x01)
        if value < 0 then value = value + 65536 end
        return value
    end

    function platform.foreground_self()
        local window = user32.GetForegroundWindow()
        if window == nil then return false end
        local owner = ffi.new('unsigned int[1]')
        user32.GetWindowThreadProcessId(window, owner)
        return owner[0] == process_id
    end

    -- The game's own window DC copies in about 0.2 ms where the desktop DC costs
    -- about 9 ms on a 3440x1440 desktop (both measured), so the window DC is the
    -- first choice. A flip-model swap chain can answer with a black surface,
    -- which the caller detects and answers by moving to the desktop DC.
    local window_handle, window_dc = nil, nil
    local rect, client_origin = ffi.new('HD2CS_RECT[1]'), ffi.new('HD2CS_POINT[1]')

    local function window_source()
        local window = user32.GetForegroundWindow()
        if window == nil or user32.IsWindow(window) == 0 then return nil end
        if window ~= window_handle then
            if window_dc ~= nil and window_handle ~= nil then user32.ReleaseDC(window_handle, window_dc) end
            window_handle, window_dc = window, user32.GetDC(window)
        end
        if window_dc == nil then return nil end
        if user32.GetClientRect(window_handle, rect) == 0 then return nil end
        if user32.ClientToScreen(window_handle, client_origin) == 0 then return nil end
        return window_dc, client_origin[0].x, client_origin[0].y, rect[0].right, rect[0].bottom
    end

    function platform.capture(center_x, center_y, options, strip_width, strip_window, source)
        if virtual.width < 8 or virtual.height < 8 then return nil end
        local width = math.min(math.floor(strip_width or options.strip_width), dib_width, virtual.width)
        local height = math.min(math.floor(strip_window or options.window) * 2, dib_height, virtual.height)
        local origin_x = clamp(math.floor(center_x - width / 2), virtual.x, virtual.x + virtual.width - width)
        local origin_y = clamp(math.floor(center_y - height / 2), virtual.y, virtual.y + virtual.height - height)
        if width < 8 or height < 16 then return nil end
        local device, source_x, source_y = screen_dc, origin_x, origin_y
        if source == 'window' then
            local dc, client_x, client_y, client_width, client_height = window_source()
            if dc == nil then return nil end
            local local_x, local_y = origin_x - client_x, origin_y - client_y
            -- Anything outside the client area is not ours to copy.
            if local_x < 0 or local_y < 0 or local_x + width > client_width
                or local_y + height > client_height then
                return nil
            end
            device, source_x, source_y = dc, local_x, local_y
        end
        local copied = gdi32.BitBlt(memory_dc, 0, 0, width, height, device, source_x, source_y,
                                   0x00CC0020 + 0x40000000) -- SRCCOPY | CAPTUREBLT
        if copied == 0 then return nil end
        -- The DIB keeps its allocated width, so rows must be read with the
        -- bitmap stride, not the captured strip width.
        local stride = dib_width * 4
        local sample = {width = width, height = height, stride = stride,
                        origin_x = origin_x, origin_y = origin_y}
        function sample.rgb(x, y)
            if x < 0 or y < 0 or x >= width or y >= height then return nil end
            local offset = y * stride + x * 4
            return pixels[offset + 2], pixels[offset + 1], pixels[offset]
        end
        return sample
    end

    -- Raw 32-bit BMP of a capture, for diagnosing what the detector sees.
    function platform.dump(sample, path)
        local width, height, stride = sample.width, sample.height, sample.stride
        local row_bytes = width * 4
        local file = io.open(path, 'wb')
        if not file then return false end
        local function u16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
        local function u32(value)
            return string.char(value % 256, math.floor(value / 256) % 256,
                               math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
        end
        local size = 54 + row_bytes * height
        file:write('BM', u32(size), u32(0), u32(54), u32(40), u32(width), u32(height),
                   u16(1), u16(32), u32(0), u32(row_bytes * height), u32(2835), u32(2835), u32(0), u32(0))
        for y = height - 1, 0, -1 do
            file:write(ffi.string(pixels + y * stride, row_bytes))
        end
        file:close()
        return true
    end

    function platform.wheel(notches)
        input[0].mi.mouseData = notches * 120
        return user32.SendInput(1, input, input_size) == 1
    end

    function platform.close()
        if window_dc ~= nil and window_handle ~= nil then user32.ReleaseDC(window_handle, window_dc) end
        window_dc, window_handle = nil, nil
        if bitmap ~= nil then gdi32.DeleteObject(bitmap) end
        if memory_dc ~= nil then gdi32.DeleteDC(memory_dc) end
        if screen_dc ~= nil then user32.ReleaseDC(nil, screen_dc) end
        bitmap, memory_dc, screen_dc = nil, nil, nil
    end

    return platform
end

-- ------------------------------------------------------------------ install

function module.install(create_platform, environment)
    local environment = environment or _G
    local loader = rawget(environment, 'CowboyBingusModLoader')
    if type(loader) ~= 'table' or (loader.api or 0) < 1 then
        return nil, 'Bingus Shared Loader API 1 is required'
    end
    if rawget(environment, 'ClickableScrollbars') then
        return nil, 'already installed'
    end
    if type(environment.update) ~= 'function' then
        return nil, 'game update callback unavailable'
    end

    local state = {
        revision = module.revision, status = 'starting', settings = module.parse_settings(nil, DEFAULTS),
        clicks = 0, pages = 0, drags = 0, corrections = 0, no_response = 0, misses = 0, skipped = 0,
        capture_failures = 0, errors = 0, frames = 0, down_frames = 0, frame_clicks = 0, last_key = 0,
        wheel_units = 0, drag_notches = 0, drag_active = false,
        captures = 0, dumps = 0, last_dump = nil,
        frame_ms_total = 0, frame_ms_max = 0, capture_ms_total = 0, capture_ms_max = 0,
        dirty = true, last_reason = 'start', last_direction = nil, last_bar = nil, last_notches = 0,
        last_delta = nil, last_moved = nil, last_luminance = nil, last_background = nil,
        last_click_luma = nil, last_bar_luma = nil,
        last_thumb_masked = nil, bar_cache = nil, last_error = nil,
        pixels_per_notch = nil, calibration = {},
    }
    rawset(environment, 'ClickableScrollbars', state)

    local function read_settings()
        local base = os.getenv('LOCALAPPDATA')
        if not base then return state.settings end
        local path = base .. '/ClickableScrollbars'
        local file = io.open(path .. '/ClickableScrollbars.ini', 'rb')
        if not file then return state.settings end
        local text = file:read(4096)
        file:close()
        return module.parse_settings(text, DEFAULTS)
    end

    local created, platform = pcall(create_platform)
    if not created then
        state.status = 'disabled: ' .. tostring(platform)
        return nil, state.status
    end
    state.settings = read_settings()
    state.status = state.settings.enabled and 'running' or 'disabled: config'

    local previous_update, previous_shutdown = environment.update, environment.shutdown
    local last_button, last_capture_ms = false, -100000
    local last_frame_ms, last_log_ms = -1, -100000
    local last_observe_ms, last_jump_ms = -100000, -100000
    local stopped = false
    local drag, thumb, jump = nil, nil, nil
    -- Notches sent since `thumb.observed_at`, so a later observation can turn
    -- the movement the game produced into a pixels-per-notch sample.
    local injected_total = 0
    local trace, reason_counts = {}, {}
    local function note(reason)
        state.last_reason = reason
        state.dirty = true
        reason_counts[reason] = (reason_counts[reason] or 0) + 1
    end

    -- The log is the addon's flight recorder: settings, counters, timing
    -- health, tracked geometry, calibration samples, a tally of every decision
    -- reason and the retained trace lines. It is rewritten (never grown) and
    -- rate limited, so diagnosis costs one file on disk and no free space.
    local function log(force)
        local now = platform.now()
        if not force then
            if not state.dirty then return end
            if now - last_log_ms < state.settings.log_interval_ms then return end
        end
        last_log_ms, state.dirty = now, false
        pcall(function()
            local file = loader.open_log and loader.open_log('ClickableScrollbars.log')
            if not file then return end
            local out = {}
            local function put(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
            put('%s', state.revision)
            put('status=%s', state.status)
            if state.last_error then put('error=%s', state.last_error) end
            put('--- settings')
            for _, key in ipairs({'enabled', 'center_tolerance', 'jump_max_notches', 'correction_notches',
                                  'max_corrections', 'settle_delay_ms', 'settle_interval_ms', 'settle_stable_px',
                                  'settle_checks', 'drag_threshold', 'drag_max_step_px', 'drag_max_notches',
                                  'calibration_samples', 'calibration_min_px', 'calibration_max_px',
                                  'cooldown_ms', 'min_capture_interval_ms', 'log_interval_ms', 'trace_lines',
                                  'trace_events', 'use_window_capture', 'error_limit', 'dump_captures',
                                  'strip_width', 'window', 'narrow_width',
                                  'narrow_window', 'min_height', 'min_width', 'max_width', 'min_luma', 'max_luma',
                                  'min_contrast', 'click_contrast', 'thumb_margin', 'column_tolerance',
                                  'bar_cache_ms'}) do
                put('%s=%s', key, tostring(state.settings[key]))
            end
            put('--- counters')
            for _, key in ipairs({'clicks', 'pages', 'drags', 'corrections', 'no_response', 'misses', 'skipped',
                                  'capture_failures', 'errors', 'frames', 'down_frames', 'frame_clicks',
                                  'wheel_units', 'drag_notches'}) do
                put('%s=%d', key, state[key] or 0)
            end
            put('--- health')
            put('capture_source=%s', tostring(state.capture_source or 'window'))
            put('capture_fallbacks=%d', state.capture_fallbacks or 0)
            put('captures=%d', state.captures)
            put('capture_ms_max=%d', state.capture_ms_max)
            put('capture_ms_avg=%.3f', state.captures > 0 and state.capture_ms_total / state.captures or 0)
            put('frame_ms_max=%d', state.frame_ms_max)
            put('frame_ms_avg=%.4f', state.frames > 0 and state.frame_ms_total / state.frames or 0)
            put('--- state')
            put('drag_active=%s', tostring(state.drag_active or false))
            put('jump_active=%s', tostring(jump ~= nil))
            put('injected_since_observe=%d', injected_total - (thumb and thumb.injected_at or injected_total))
            put('last_reason=%s', tostring(state.last_reason))
            put('last_direction=%s', tostring(state.last_direction or 'none'))
            put('last_notches=%d', state.last_notches or 0)
            put('last_delta=%s', tostring(state.last_delta or 'none'))
            put('last_moved=%s', tostring(state.last_moved or 'none'))
            put('pixels_per_notch=%s', state.pixels_per_notch and string.format('%.2f', state.pixels_per_notch)
                or 'none')
            local samples = {}
            for index = 1, #state.calibration do samples[index] = string.format('%.2f', state.calibration[index]) end
            put('calibration=%s', #samples > 0 and table.concat(samples, ',') or 'none')
            local bar = state.last_bar
            put('last_bar=%s', bar and (bar.left .. ',' .. bar.top .. ',' .. bar.right .. ',' .. bar.bottom)
                or 'none')
            put('last_bar_masked=%s', tostring(state.last_thumb_masked or false))
            local cache = state.bar_cache
            put('bar_cache=%s', cache and (cache.left .. ',' .. cache.right) or 'none')
            local tracked = thumb
            put('thumb=%s', tracked and string.format('%d..%d centre=%.1f height=%s', tracked.left, tracked.right,
                tracked.center_y, tostring(tracked.height)) or 'none')
            put('last_luminance=%s', tostring(state.last_luminance or 'none'))
            put('last_click_luma=%s', state.last_click_luma and string.format('%.1f', state.last_click_luma)
                or 'none')
            put('last_bar_luma=%s', state.last_bar_luma and string.format('%.1f', state.last_bar_luma) or 'none')
            put('background_luma=%s', tostring(state.last_background or 'none'))
            put('last_dump=%s', tostring(state.last_dump or 'none'))
            local names = {}
            for name in pairs(reason_counts) do names[#names + 1] = name end
            table.sort(names)
            local summary = {}
            for _, name in ipairs(names) do
                summary[#summary + 1] = name .. '=' .. reason_counts[name]
            end
            put('reason_counts=%s', #summary > 0 and table.concat(summary, ',') or 'none')
            put('--- trace')
            put('trace_lines=%d', #trace)
            for _, line in ipairs(trace) do put('trace %s', line) end
            file:write(table.concat(out, '\n') .. '\n')
            file:close()
        end)
    end

    local function per_notch()
        return state.pixels_per_notch or state.settings.default_pixels_per_notch
    end

    local function record(fmt, ...)
        local line = select('#', ...) > 0 and string.format(fmt, ...) or fmt
        trace[#trace + 1] = string.format('%d %s', math.floor(platform.now()), line)
        while #trace > state.settings.trace_lines do table.remove(trace, 1) end
        state.dirty = true
    end

    -- The median of the recent observations, so one bad measurement (a clamped
    -- list end, a half-hidden thumb) cannot bias the step the pointer uses.
    local function push_calibration(value)
        state.calibration[#state.calibration + 1] = value
        while #state.calibration > state.settings.calibration_samples do
            table.remove(state.calibration, 1)
        end
        local sorted = {}
        for index = 1, #state.calibration do sorted[index] = state.calibration[index] end
        table.sort(sorted)
        state.pixels_per_notch = sorted[math.floor((#sorted + 1) / 2)]
    end

    -- One notch, one wheel event, sent now. Nothing is paced, queued or
    -- re-scheduled: the pointer is the only clock this addon obeys.
    local function emit(units)
        if not units or units == 0 then return 0 end
        local step = units > 0 and 1 or -1
        for _ = 1, math.abs(units) do platform.wheel(step) end
        local sent = step * math.abs(units)
        injected_total = injected_total + sent
        state.wheel_units = (state.wheel_units or 0) + sent
        state.last_notches = sent
        if thumb then
            thumb.center_y = thumb.observed_y - (injected_total - thumb.injected_at) * per_notch()
        end
        if state.settings.trace_events == 1 then
            record('emit units=%d predicted=%s', sent, thumb and string.format('%.1f', thumb.center_y) or 'none')
        end
        return sent
    end

    -- Captures are the expensive part (a GDI blit plus a pixel scan), so they
    -- run only when a decision needs one and their cost is measured for the log.
    local function raw_capture(center_x, center_y, options, width, height, source)
        local started = platform.now()
        local sample = platform.capture(center_x, center_y, options, width, height, source)
        local elapsed = platform.now() - started
        state.captures = state.captures + 1
        state.capture_ms_total = state.capture_ms_total + elapsed
        if elapsed > state.capture_ms_max then state.capture_ms_max = elapsed end
        return sample
    end

    -- The window DC is roughly forty times cheaper than the desktop DC, but it
    -- can answer with a black surface (or a stale one) for an exclusive or
    -- flip-model swap chain. The first capture of the session therefore copies
    -- from both and keeps the window path only when the two agree; after that
    -- the choice stands until a capture comes back black, which switches it to
    -- the desktop DC for good. Both the choice and its cost are logged.
    local function timed_capture(center_x, center_y, options, width, height)
        local source = state.settings.use_window_capture == 1 and (state.capture_source or 'window') or 'screen'
        local sample = raw_capture(center_x, center_y, options, width, height, source)
        if source == 'screen' then
            state.capture_source = 'screen'
            return sample
        end
        local average = sample and module.strip_luminance(sample)
        local usable = sample ~= nil and average ~= nil and average >= 6
        if usable and not state.capture_validated then
            local reference = raw_capture(center_x, center_y, options, width, height, 'screen')
            local reference_average = reference and module.strip_luminance(reference)
            state.capture_validated = true
            usable = reference ~= nil and reference_average ~= nil
                and math.abs(reference_average - average) <= 20
            record('capture window %s window=%s screen=%s', usable and 'kept' or 'rejected',
                   tostring(average), tostring(reference_average))
            if not usable then sample = reference end
        end
        if usable then
            state.capture_source = 'window'
            return sample
        end
        state.capture_fallbacks = (state.capture_fallbacks or 0) + 1
        state.capture_source = 'screen'
        record('capture window unusable (%s); using the desktop DC', tostring(average))
        if sample == nil then sample = raw_capture(center_x, center_y, options, width, height, 'screen') end
        return sample
    end

    -- One analysis pass: brightness sanity, optional diagnostic dump, detect.
    local function analysis_for(sample, cursor_x, cursor_y, band)
        local average = module.strip_luminance(sample)
        state.last_luminance = average
        if average ~= nil and average < 6 then
            state.capture_failures = state.capture_failures + 1
            return nil, 'capture_black'
        end
        if state.dumps < state.settings.dump_captures and platform.dump then
            local directory = loader.log_directory or os.getenv('LOCALAPPDATA')
            if directory then
                state.dumps = state.dumps + 1
                local path = string.format('%s/ClickableScrollbars-capture-%d-%dx%d.bmp',
                    directory, state.dumps, cursor_x, cursor_y)
                if platform.dump(sample, path) then state.last_dump = path end
            end
        end
        local local_cursor = {x = cursor_x - sample.origin_x, y = cursor_y - sample.origin_y}
        local action, reason = module.analyse(sample, local_cursor, state.settings, band)
        state.last_background = sample.background
        -- One pixel of context: when a press is refused because the pixel under
        -- the pointer is not dark enough to be the track, the log can then show
        -- whether the pointer's own tint lifted it or the click really landed on
        -- list content.
        local click_r, click_g, click_b = sample.rgb(local_cursor.x, local_cursor.y)
        state.last_click_luma = click_r and luminance(click_r, click_g, click_b) or nil
        if not action then return nil, reason end
        state.last_bar_luma = action.bar.median
        action.bar_screen = {
            left = sample.origin_x + action.bar.left,
            right = sample.origin_x + action.bar.right,
            top = sample.origin_y + action.bar.top,
            bottom = sample.origin_y + action.bar.bottom,
        }
        return action, reason
    end

    -- Cost control: once a bar column is known, a narrow re-check usually
    -- answers a click; the wide scan only runs when that fails.
    local function capture_analysis(cursor_x, cursor_y, now)
        local cached = state.bar_cache
        if cached and now - cached.at <= state.settings.bar_cache_ms
            and cursor_x >= cached.left - 40 and cursor_x <= cached.right + 40 then
            local center = math.floor((cached.left + cached.right) / 2)
            local sample = timed_capture(center, cursor_y, state.settings,
                                         state.settings.narrow_width, state.settings.narrow_window)
            if sample then
                local band = {left = cached.left - sample.origin_x - state.settings.column_tolerance,
                              right = cached.right - sample.origin_x + state.settings.column_tolerance}
                local action, reason = analysis_for(sample, cursor_x, cursor_y, band)
                if action and cursor_x >= action.bar_screen.left - state.settings.column_tolerance
                    and cursor_x <= action.bar_screen.right + state.settings.column_tolerance then
                    return action, reason
                end
            end
        end
        local sample = timed_capture(cursor_x, cursor_y, state.settings)
        if not sample then
            state.capture_failures = state.capture_failures + 1
            return nil, 'capture_failed'
        end
        local action, reason = analysis_for(sample, cursor_x, cursor_y)
        if action then
            state.bar_cache = {left = action.bar_screen.left, right = action.bar_screen.right, at = now}
        end
        return action, reason
    end

    -- The thumb is tracked between captures: an injected notch moves it by
    -- about one wheel step, so the estimate stays usable while the cursor's own
    -- glow hides the bar, and every fresh observation re-anchors it.
    local function measure(sample, band, cursor)
        local tuned = module.adapt_options(sample, state.settings)
        local best = module.find_thumb(sample, cursor, tuned, band)
        if not best then return nil end
        local top, bottom = best.top + sample.origin_y, best.bottom + sample.origin_y
        local known = state.thumb_height
        if best.clipped_top and not best.clipped_bottom and known then
            return bottom - known / 2
        elseif best.clipped_bottom and not best.clipped_top and known then
            return top + known / 2
        elseif best.clipped_top and best.clipped_bottom then
            return nil
        end
        local height = bottom - top
        -- Only an unclipped run has a trustworthy height: a fragment beside the
        -- pointer sprite would otherwise teach the tracker a thumb that is far
        -- too short.
        if not best.clipped_top and not best.clipped_bottom and height >= 20
            and (not known or math.abs(height - known) < 10) then
            state.thumb_height = height
            if thumb then thumb.height = height end
        end
        return (top + bottom) / 2
    end

    -- Look for the bar where it should now be. The cursor is passed to the
    -- detector so the glow it draws over the thumb is masked and bridged (the
    -- pointer sits on the bar throughout a settle), and a full-width retry
    -- runs when the narrow window misses, so a bar that moved or overshot is
    -- still measured instead of abandoning the pass.
    local function observe(target_y)
        if not thumb then return nil end
        local center_x = math.floor((thumb.left + thumb.right) / 2)
        local cursor_x, cursor_y = platform.cursor()
        local band = nil
        local sample = timed_capture(center_x, target_y, state.settings,
                                     state.settings.narrow_width, state.settings.narrow_window)
        if sample then
            band = {left = thumb.left - sample.origin_x - state.settings.column_tolerance,
                    right = thumb.right - sample.origin_x + state.settings.column_tolerance}
            local local_cursor = cursor_x and {x = cursor_x - sample.origin_x, y = cursor_y - sample.origin_y} or nil
            local center = measure(sample, band, local_cursor)
            if center then return center end
        end
        local wide = timed_capture(center_x, target_y, state.settings)
        if not wide then return nil end
        band = {left = thumb.left - wide.origin_x - state.settings.column_tolerance,
                right = thumb.right - wide.origin_x + state.settings.column_tolerance}
        local local_cursor = cursor_x and {x = cursor_x - wide.origin_x, y = cursor_y - wide.origin_y} or nil
        return measure(wide, band, local_cursor)
    end

    -- Re-anchor the tracked thumb on a measurement and, when notches were sent
    -- since the previous one, learn the wheel step the game actually produced.
    local function note_observation(center, now, settled)
        if thumb then
            -- Only a stopped thumb measures the wheel step: while the list is
            -- still gliding, the displacement understates it, and an
            -- understated step is what makes a correction overshoot. The anchor
            -- therefore moves only on a settled reading, while the live
            -- estimate follows every reading.
            if settled then
                local moved = injected_total - thumb.injected_at
                if moved ~= 0 then
                    local observed = math.abs(center - thumb.observed_y) / math.abs(moved)
                    if observed >= state.settings.calibration_min_px
                        and observed <= state.settings.calibration_max_px then
                        push_calibration(observed)
                    end
                end
                thumb.observed_y, thumb.observed_at, thumb.injected_at = center, now, injected_total
            end
            thumb.center_y = center
        end
    end

    -- The verification pass after a jump. It never chases the game's own
    -- animation: a correction needs the thumb to have stopped moving, it is
    -- only sent when the predicted step is smaller than the residual it
    -- removes, and there is at most max_corrections of them per jump. So the
    -- worst case is "burst, one small nudge", never a visible bounce.
    local function service_jump(now)
        if not jump then return end
        if now < jump.next_check then return end
        if now - last_observe_ms < state.settings.settle_interval_ms then return end
        last_observe_ms = now
        jump.checks = jump.checks + 1
        local centre = observe(jump.target_y)
        if not centre then
            if jump.checks >= state.settings.settle_checks then
                note('jump_unobserved')
                record('settle give_up observed=none checks=%d', jump.checks)
                jump = nil
            else
                jump.next_check = now + state.settings.settle_interval_ms
            end
            return
        end
        local residual = jump.target_y - centre
        local stable = jump.last_centre and math.abs(centre - jump.last_centre) <= state.settings.settle_stable_px
        note_observation(centre, now, stable)
        jump.last_centre = centre
        state.last_delta = residual
        state.last_moved = jump.baseline and (centre - jump.baseline) or nil
        if state.settings.trace_events == 1 or not stable then
            record('settle centre=%.1f residual=%.1f stable=%s check=%d/%d', centre, residual, tostring(stable),
                   jump.checks, state.settings.settle_checks)
        end
        if not stable then
            -- Still moving: watch it again without touching it.
            if jump.checks >= state.settings.settle_checks then
                note('settle_timeout')
                jump = nil
            else
                jump.next_check = now + state.settings.settle_interval_ms
            end
            return
        end
        if math.abs(residual) <= state.settings.center_tolerance then
            note('centered')
            record('settle centred residual=%.1f', residual)
            jump = nil
            return
        end
        if jump.baseline and math.abs(centre - jump.baseline) <= state.settings.settle_stable_px
            and math.abs(jump.injected) >= 2 then
            -- The bar did not move at all for a multi-notch burst: this is the
            -- list end (or the game ignored the wheel). Either way, nudging
            -- again would only chatter.
            state.no_response = state.no_response + 1
            note('no_response')
            record('settle no_response residual=%.1f injected=%d', residual, jump.injected)
            jump = nil
            return
        end
        -- Round, never round up: a residual below half a notch is left alone,
        -- which is what stops a repeat click at the same spot from moving.
        local units = math.floor(math.abs(residual) / math.max(per_notch(), 1) + 0.5)
        units = math.min(units, state.settings.correction_notches)
        if units == 0 then
            note('close_enough')
            jump = nil
            return
        end
        if jump.corrections >= state.settings.max_corrections then
            note('settled_max')
            jump = nil
            return
        end
        emit(residual > 0 and -units or units)
        jump.corrections = jump.corrections + 1
        jump.injected = jump.injected + (residual > 0 and -units or units)
        jump.baseline = centre
        jump.last_centre = nil -- the moved thumb needs a fresh stable pair
        jump.next_check = now + state.settings.settle_delay_ms
        state.corrections = state.corrections + 1
        note('correcting')
        record('settle correct residual=%.1f units=%d per_notch=%.1f',
               residual, residual > 0 and -units or units, per_notch())
    end

    local function handle_press(now)
        state.clicks = state.clicks + 1
        if not state.settings.enabled then
            state.skipped = state.skipped + 1
            note('disabled')
            return
        end
        if not platform.foreground_self() then
            state.skipped = state.skipped + 1
            note('not_foreground')
            return
        end
        local cursor_x, cursor_y = platform.cursor()
        if not cursor_x then
            state.skipped = state.skipped + 1
            note('no_cursor')
            return
        end
        if now - last_capture_ms < state.settings.min_capture_interval_ms then
            state.skipped = state.skipped + 1
            note('rate_limited')
            return
        end
        last_capture_ms = now
        local action, reason = capture_analysis(cursor_x, cursor_y, now)
        note(reason or 'none')
        if not action and thumb and now - thumb.observed_at <= state.settings.bar_cache_ms
            and cursor_x >= thumb.left - state.settings.column_tolerance
            and cursor_x <= thumb.right + state.settings.column_tolerance then
            -- The bar is under the cursor but the glow hid it: fall back to the
            -- tracked geometry so the press still grabs the bar.
            local center = thumb.center_y
            action = {hit = 'thumb', bar = {masked = true},
                      cached = true,
                      bar_screen = {left = thumb.left, right = thumb.right,
                                    top = center - thumb.height / 2,
                                    bottom = center + thumb.height / 2}}
            note('thumb_cached')
        end
        if not action then
            state.misses = state.misses + 1
            state.last_bar = nil
            record('click x=%d y=%d refused=%s pixel=%s bar=%s', cursor_x, cursor_y, tostring(reason),
                   state.last_click_luma and string.format('%.0f', state.last_click_luma) or 'none',
                   state.last_bar_luma and string.format('%.0f', state.last_bar_luma) or 'none')
            return
        end
        local bar = action.bar_screen
        local run_height = bar.bottom - bar.top + 1
        local known_height = state.thumb_height
        local centre = (bar.top + bar.bottom) / 2
        if state.bar_cache and math.abs(state.bar_cache.left - bar.left) > 6 then
            -- A different column: any learned thumb height belonged to the old bar.
            state.thumb_height, known_height = nil, nil
        end
        if not action.cached then
            -- The glow can hide one end of the thumb; when the height is known
            -- the hidden end is inferred from the visible one, so a press on or
            -- beside the bar still aims at its true centre.
            if action.bar.clipped_top and not action.bar.clipped_bottom and known_height then
                centre = bar.bottom - known_height / 2
            elseif action.bar.clipped_bottom and not action.bar.clipped_top and known_height then
                centre = bar.top + known_height / 2
            end
            if not action.bar.clipped_top and not action.bar.clipped_bottom and run_height >= 20 then
                state.thumb_height, known_height = run_height, run_height
            end
            thumb = {left = bar.left, right = bar.right, height = known_height or run_height,
                     observed_y = centre, observed_at = now, injected_at = injected_total, center_y = centre}
        elseif thumb and math.abs(thumb.left - bar.left) > 6 then
            thumb = nil
        elseif thumb then
            centre = thumb.center_y
        end
        state.last_bar = bar
        state.last_thumb_masked = action.bar.masked and true or false
        jump = nil
        drag = {start_x = cursor_x, start_y = cursor_y, last_y = cursor_y, active = false,
                fraction = 0, total = 0}
        record('click x=%d y=%d hit=%s bar=%d,%d,%d,%d masked=%s per_notch=%.1f', cursor_x, cursor_y,
               tostring(action.hit), bar.left, bar.top, bar.right, bar.bottom,
               tostring(action.bar.masked), per_notch())
        if action.hit == 'thumb' then
            note('bar_press')
            return
        end
        local centre = (bar.top + bar.bottom) / 2
        local delta = cursor_y - centre
        state.last_delta = delta
        -- Rounding down to a whole wheel step is what makes a repeat click on
        -- an already-centred thumb a true no-op: a residual below half a step
        -- is left alone instead of being rounded up into a visible nudge.
        local units = math.floor(math.abs(delta) / math.max(per_notch(), 1) + 0.5)
        if units == 0 then
            note('already_centered')
            record('jump skipped delta=%.1f (within half a step)', delta)
            return
        end
        if now - last_jump_ms < state.settings.cooldown_ms then
            state.skipped = state.skipped + 1
            note('cooldown')
            return
        end
        last_jump_ms = now
        units = math.min(units, state.settings.jump_max_notches)
        local sent = emit(delta > 0 and -units or units)
        state.pages = state.pages + 1
        state.last_direction = delta > 0 and 'down' or 'up'
        jump = {target_y = cursor_y, baseline = centre, injected = sent, corrections = 0, checks = 0,
                next_check = now + state.settings.settle_delay_ms}
        note(delta > 0 and 'jump_down' or 'jump_up')
        record('jump target=%.1f centre=%.1f delta=%.1f units=%d per_notch=%.1f', cursor_y, centre, delta,
               sent, per_notch())
        log(false)
    end

    local function frame()
        local now = platform.now()
        if now == last_frame_ms then return end
        last_frame_ms = now
        state.frames = state.frames + 1
        state.last_key = platform.key_state and platform.key_state() or 0
        local down = platform.pressed()
        if down then state.down_frames = state.down_frames + 1 end
        local pressed = down and not last_button
        last_button = down
        -- Drag: the thumb travels exactly as far as the mouse. The distance is
        -- converted with the learned wheel step and sent on the frame it was
        -- measured, so no scheduler sits between the hand and the bar.
        if drag then
            if not down then
                if drag.active then
                    note('drag_end')
                    record('drag_end units=%d', drag.total or 0)
                end
                drag, state.drag_active = nil, false
            else
                local cursor_x, cursor_y = platform.cursor()
                if cursor_x then
                    local moved_x, moved_y = cursor_x - drag.start_x, cursor_y - drag.start_y
                    if not drag.active and math.abs(moved_y) > state.settings.drag_threshold
                        and math.abs(moved_y) >= math.abs(moved_x) then
                        drag.active, state.drag_active = true, true
                        drag.last_y, drag.fraction = drag.start_y, 0
                        jump = nil
                        state.drags = state.drags + 1
                        note('drag_start')
                        record('drag_start y=%d threshold=%d', cursor_y, state.settings.drag_threshold)
                    end
                    if drag.active then
                        local delta = cursor_y - drag.last_y
                        if math.abs(delta) > state.settings.drag_max_step_px then
                            -- The pointer teleported (alt-tab, display change):
                            -- re-baseline instead of flinging the list.
                            record('drag_resync delta=%d', delta)
                        elseif delta ~= 0 then
                            drag.fraction = drag.fraction - delta / math.max(per_notch(), 1)
                            local steps = math.floor(math.abs(drag.fraction))
                            if steps > 0 then
                                local step = drag.fraction > 0 and 1 or -1
                                if steps > state.settings.drag_max_notches then
                                    record('drag_clamped steps=%d per_notch=%.1f', steps, per_notch())
                                    steps, drag.fraction = state.settings.drag_max_notches, 0
                                else
                                    drag.fraction = drag.fraction - step * steps
                                end
                                emit(step * steps)
                                drag.total = (drag.total or 0) + steps
                                state.drag_notches = (state.drag_notches or 0) + steps
                                state.last_direction = step > 0 and 'up' or 'down'
                                if state.settings.trace_events == 1 then
                                    record('drag_move delta=%d units=%d', delta, step * steps)
                                end
                            end
                        end
                        drag.last_y = cursor_y
                    end
                end
            end
        end
        if pressed then
            state.frame_clicks = state.frame_clicks + 1
            handle_press(now)
        end
        service_jump(now)
        local elapsed = platform.now() - now
        state.frame_ms_total = state.frame_ms_total + elapsed
        if elapsed > state.frame_ms_max then state.frame_ms_max = elapsed end
        log(false)
    end

    -- A failing frame must not take the feature down for the session: the error
    -- is counted, recorded with its full message, the frame's half-finished
    -- interaction is dropped, and the addon only stops after error_limit
    -- failures, so a one-off hiccup is diagnosed instead of ending the mod.
    local function guard(label)
        local ok, reason = pcall(frame)
        if ok then return true end
        state.errors = state.errors + 1
        state.last_error = tostring(reason)
        drag, state.drag_active, jump = nil, false, nil
        note('frame_error')
        record('error %s #%d: %s', label, state.errors, tostring(reason))
        if state.errors >= state.settings.error_limit then
            stopped = true
            state.status = 'stopped: ' .. tostring(reason)
        end
        log(true)
        return false
    end

    environment.update = function(dt, ...)
        if not stopped then guard('update') end
        if type(previous_update) == 'function' then
            return previous_update(dt, ...)
        end
    end
    environment.shutdown = function(...)
        stopped = true
        state.status = 'stopped'
        record('shutdown frames=%d clicks=%d pages=%d', state.frames or 0, state.clicks or 0, state.pages or 0)
        log(true)
        pcall(platform.close)
        if type(previous_shutdown) == 'function' then
            return previous_shutdown(...)
        end
    end

    -- The engine also drives a per-frame render callback. Running the same
    -- frame body there keeps the addon alive if a future build stops calling
    -- the Lua update global; the millisecond guard collapses duplicates.
    local previous_render = rawget(environment, 'render')
    if type(previous_render) == 'function' then
        environment.render = function(...)
            if not stopped then guard('render') end
            return previous_render(...)
        end
    end

    state.status = state.settings.enabled and 'running' or 'disabled: config'
    log(true)
    return state
end

if rawget(_G, '__CLICKABLE_SCROLLBARS_TEST') then
    return module
end

local ok, reason = module.install(module.create_platform)
if not ok then
    local loader = rawget(_G, 'CowboyBingusModLoader')
    print('[ClickableScrollbars] ' .. tostring(reason))
    pcall(function()
        local file = loader and loader.open_log and loader.open_log('ClickableScrollbars.log')
        if file then
            file:write(module.revision .. '\nstatus=' .. tostring(reason) .. '\n')
            file:close()
        end
    end)
end
