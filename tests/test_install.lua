-- Runtime tests for the Clickable Scrollbars addon.
--
-- The platform is faked: the thumb is a scripted rectangle that moves by a
-- fixed number of pixels per injected wheel notch, which lets the aiming, the
-- calibration, the drag follow, the guards and the log be checked without
-- Windows or the game. Each numbered case pins one behaviour that was wrong in
-- an earlier build: paced emission (lag), queued drain (running on after the
-- pointer stopped), rounded-up residuals (repeat clicks moving) and repeated
-- settle passes (visible back-and-forth).

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

local function new_platform(options)
    if type(options) == 'number' or options == nil then options = {shift = options} end
    local shift = options.shift
    local platform = {wheels = {}, closed = false, captures = 0}
    platform.state = {
        now = 1000, cursor = {x = 900, y = 400}, down = false, foreground = true,
        bar = {left = 880, right = 891, top = 460, bottom = 700}, shift = shift or 13,
        display_height = options.display_height,
    }
    function platform.now() return platform.state.now end
    function platform.cursor() return platform.state.cursor.x, platform.state.cursor.y end
    function platform.pressed() return platform.state.down end
    function platform.key_state() return 0 end
    function platform.foreground_self() return platform.state.foreground end
    function platform.display_height() return platform.state.display_height end
    function platform.close() platform.closed = true end
    function platform.wheel(notches)
        platform.wheels[#platform.wheels + 1] = notches
        if platform.ignore_wheel then return true end
        local bar = platform.state.bar
        local step = platform.state.shift * (notches > 0 and -1 or 1)
        bar.top, bar.bottom = bar.top + step, bar.bottom + step
        return true
    end
    function platform.capture(center_x, center_y, options, strip_width, strip_window)
        platform.captures = platform.captures + 1
        local width = math.min(strip_width or options.strip_width, 160)
        local height = math.min((strip_window or options.window) * 2, platform.capture_cap or 1100)
        local origin_x = center_x - math.floor(width / 2)
        local origin_y = center_y - math.floor(height / 2)
        local bar = platform.state.bar
        local function rgb(x, y)
            local screen_x, screen_y = origin_x + x, origin_y + y
            if screen_x >= bar.left and screen_x <= bar.right
                and screen_y >= bar.top and screen_y <= bar.bottom then
                return 149, 149, 149
            end
            return 45, 45, 45
        end
        return {width = width, height = height, origin_x = origin_x, origin_y = origin_y, rgb = rgb}
    end
    function platform.bar_center()
        return (platform.state.bar.top + platform.state.bar.bottom) / 2
    end
    return platform
end

local function new_environment(sink)
    return {
        update = function() return 'previous' end,
        shutdown = function() return 'previous-shutdown' end,
        CowboyBingusModLoader = {
            api = 1,
            open_log = function(name)
                if not sink then return nil end
                return {write = function(_, text) sink[#sink + 1] = text end, close = function() end}
            end,
        },
    }
end

local function boot(shift, sink)
    local platform = new_platform(shift)
    local environment = new_environment(sink)
    environment.__platform = platform
    local state = module.install(function() return platform end, environment)
    return platform, environment, state
end

local function tick(platform, environment, milliseconds)
    platform.state.now = platform.state.now + (milliseconds or 32)
    environment.update(0.016)
end

local function drain(platform, environment, milliseconds, step)
    local elapsed = 0
    while elapsed < (milliseconds or 1500) do
        tick(platform, environment, step)
        elapsed = elapsed + (step or 32)
    end
end

local function press(platform, environment, x, y)
    platform.state.down = false
    tick(platform, environment)
    platform.state.cursor = {x = x, y = y}
    platform.state.down = true
    tick(platform, environment)
end

-- ---------------------------------------------------------------- 1. the jump

local platform, environment, state = boot(13)
check('install returns state', type(state) == 'table' and state.status == 'running', state and state.status)
check('update wrapper installed', environment.update ~= nil)

local target = 300
press(platform, environment, 886, target)
local expected_burst = math.floor((580 - target) / 13 + 0.5)
check('the whole burst goes out on the click frame', #platform.wheels == expected_burst, #platform.wheels)
check('burst direction is up', state.last_direction == 'up' and state.last_notches == expected_burst,
    tostring(state.last_direction) .. '/' .. tostring(state.last_notches))
drain(platform, environment, 1200)
-- Whole wheel notches quantise the aim, so the best possible result is half a
-- step from the pointer; the point of the test is that it stops there instead
-- of hunting the last few pixels.
check('the thumb lands within half a wheel step', math.abs(platform.bar_center() - target) <= 7,
    platform.bar_center())
check('a burst that lands close enough is left alone', state.corrections == 0
    and (state.last_reason == 'centered' or state.last_reason == 'close_enough'),
    state.last_reason .. ' corrections=' .. state.corrections)
check('nothing is emitted after the thumb settles', #platform.wheels == expected_burst, #platform.wheels)
check('the wheel step was calibrated from the observation', state.pixels_per_notch ~= nil
    and math.abs(state.pixels_per_notch - 13) < 1, tostring(state.pixels_per_notch))

-- --------------------------------------------------- 2. repeat click, no move

local before_repeat = #platform.wheels
press(platform, environment, 886, target + 5)
check('a press on the thumb is a grab, not a jump', state.last_reason == 'bar_press', state.last_reason)
platform.state.down = false
tick(platform, environment)
platform.state.now = platform.state.now + 2000
press(platform, environment, 886, target + 5)
drain(platform, environment, 600)
check('clicking the same spot again moves nothing', #platform.wheels == before_repeat,
    #platform.wheels - before_repeat)

-- --------------------------------------------------------- 3. click below/above

platform.state.down = false
tick(platform, environment)
platform.state.now = platform.state.now + 2000
press(platform, environment, 886, 520)
drain(platform, environment, 900)
check('a click below jumps the thumb down', math.abs(platform.bar_center() - 520) <= 7,
    platform.bar_center())
check('down direction recorded', state.last_direction == 'down', state.last_direction)

-- ------------------------------------------------------- 4. drag follows 1:1

local drag, drag_environment, drag_state = boot(13)
press(drag, drag_environment, 886, drag.bar_center())
check('a grab is recognised', drag_state.last_reason == 'bar_press', drag_state.last_reason)
local captures_before = drag.captures
local wheels_before = #drag.wheels
local start_center = drag.bar_center()
drag.state.cursor = {x = 886, y = drag.bar_center() + 39}
tick(drag, drag_environment)
check('a drag emits in the same frame it moves', #drag.wheels == wheels_before + 3, #drag.wheels - wheels_before)
check('a drag never captures pixels', drag.captures == captures_before, drag.captures - captures_before)
for step = 2, 8 do
    drag.state.cursor = {x = 886, y = start_center + step * 39}
    tick(drag, drag_environment)
end
local travelled = drag.bar_center() - start_center
check('the thumb travels exactly as far as the mouse', math.abs(travelled - 312) <= 1, travelled)
check('no capture happened during the drag', drag.captures == captures_before,
    drag.captures - captures_before)
drag.state.down = false
tick(drag, drag_environment)
drain(drag, drag_environment, 400)
check('the drag stops on release', drag_state.drag_active == false and drag_state.last_reason == 'drag_end',
    drag_state.last_reason)
check('nothing is emitted after release', #drag.wheels - wheels_before == math.floor(312 / 13 + 0.5),
    #drag.wheels - wheels_before)

-- ------------------------------------------- 5. a teleport must not fling it

local teleport, teleport_environment, teleport_state = boot(13)
press(teleport, teleport_environment, 886, teleport.bar_center())
teleport.state.cursor = {x = 886, y = teleport.bar_center() + 40}
tick(teleport, teleport_environment)
local after_drag_start = #teleport.wheels
teleport.state.cursor = {x = 886, y = teleport.bar_center() + 600}
tick(teleport, teleport_environment)
check('a pointer teleport does not scroll', #teleport.wheels == after_drag_start,
    #teleport.wheels - after_drag_start)
check('the teleport is logged', teleport_state.last_reason == 'drag_start', teleport_state.last_reason)

-- ------------------------------- 6. a game with a different step: bounded nudges

local odd, odd_environment, odd_state = boot(20)
press(odd, odd_environment, 886, 760)
local burst = #odd.wheels
drain(odd, odd_environment, 3000)
local total = #odd.wheels
check('a mismatched step is corrected', burst > 0 and total > burst, total)
check('at most max_corrections nudges', odd_state.corrections <= 2, odd_state.corrections)
check('the corrected thumb is near the cursor', math.abs(odd.bar_center() - 760) <= 20,
    odd.bar_center())
drain(odd, odd_environment, 2000)
check('the correction stops instead of chattering', #odd.wheels == total, #odd.wheels - total)
check('the step was re-learned', odd_state.pixels_per_notch ~= nil
    and math.abs(odd_state.pixels_per_notch - 20) < 3, tostring(odd_state.pixels_per_notch))

-- ------------------------------------- 7. a game that ignores the wheel reports it

local deaf, deaf_environment, deaf_state = boot(13)
deaf.ignore_wheel = true
press(deaf, deaf_environment, 886, 760)
local deaf_burst = #deaf.wheels
drain(deaf, deaf_environment, 2000)
check('an ignored wheel is reported', deaf_state.last_reason == 'no_response' and deaf_state.no_response == 1,
    deaf_state.last_reason)
check('an ignored wheel is not chased', #deaf.wheels == deaf_burst and deaf_state.corrections == 0,
    #deaf.wheels)

-- --------------------------------------------------------- 8. no thumb, guards

local empty, empty_environment, empty_state = boot(13)
empty.state.bar = {left = -10, right = -5, top = -60, bottom = -50}
press(empty, empty_environment, 886, 300)
drain(empty, empty_environment, 300)
check('a click with no thumb does nothing', #empty.wheels == 0 and empty_state.last_reason == 'no_thumb',
    empty_state.last_reason)

empty.state.bar = {left = 880, right = 891, top = 460, bottom = 700}
empty.state.foreground = false
empty.state.now = empty.state.now + 2000
press(empty, empty_environment, 886, 300)
check('a background click is ignored', #empty.wheels == 0 and empty_state.last_reason == 'not_foreground',
    empty_state.last_reason)

empty.state.foreground = true
empty.state.now = empty.state.now + 2000
empty.capture = function() return nil end
press(empty, empty_environment, 886, 300)
check('a failed capture is reported', empty_state.last_reason == 'capture_failed'
    and empty_state.capture_failures > 0, empty_state.last_reason)

-- ------------------------------------------- 9. a throwing frame is not fatal

local broken, broken_environment, broken_state = boot(13)
broken_state.settings.error_limit = 2
broken.capture = function() error('capture exploded') end
press(broken, broken_environment, 886, 300)
check('one bad frame is counted, not fatal', broken_state.errors == 1 and broken_state.status == 'running',
    broken_state.status .. ' errors=' .. broken_state.errors)
check('the error text is kept for the log', tostring(broken_state.last_error):match('capture exploded') ~= nil,
    tostring(broken_state.last_error))
press(broken, broken_environment, 886, 300)
check('error_limit stops the addon', broken_state.errors == 2
    and broken_state.status:match('^stopped'), broken_state.status)

-- ------------------------------------------------------------- 10. the log

local sink = {}
local logged, logged_environment, logged_state = boot(13, sink)
press(logged, logged_environment, 886, 300)
drain(logged, logged_environment, 1500)
logged_environment.shutdown()
local text = table.concat(sink)
check('the log is written', #text > 0)
check('the log reports the revision and status', text:match('^v%d[%d%.]*\n') ~= nil
    and text:match('status=running') ~= nil, text:sub(1, 40))
check('the log carries the settings in force', text:match('center_tolerance=') ~= nil
    and text:match('max_corrections=') ~= nil and text:match('drag_max_notches=') ~= nil)
check('the log carries the counters', text:match('\npages=1\n') ~= nil and text:match('\nclicks=') ~= nil
    and text:match('\nerrors=0\n') ~= nil)
check('the log carries timing health', text:match('capture_ms_avg=') ~= nil
    and text:match('frame_ms_avg=') ~= nil and text:match('captures=') ~= nil)
check('the log carries the tracked state', text:match('pixels_per_notch=') ~= nil
    and text:match('\ntrace ') ~= nil and text:match('reason_counts=') ~= nil
    and text:match('last_bar=') ~= nil)
check('the log is rate limited, not per frame', #sink <= 12, #sink)
check('no capture images are written unless asked', logged_state.dumps == 0 and logged_state.last_dump == nil,
    tostring(logged_state.last_dump))

-- ------------------------------------------------------------- 11. shutdown

local closed, closed_environment, closed_state = boot(13)
local result = closed_environment.shutdown()
check('shutdown forwards the previous callback', result == 'previous-shutdown' and closed.closed,
    tostring(result))
check('shutdown marks the addon stopped', closed_state.status == 'stopped', closed_state.status)

-- ------------------------------------------------------- 12. settings plumbing

local configured = module.parse_settings('enabled=0\ndrag_threshold=25\ncenter_tolerance=9\n', nil)
check('settings parse overrides', configured.enabled == false and configured.drag_threshold == 25
    and configured.center_tolerance == 9 and configured.strip_width == 96)

-- ------------------------------------- 13. the cheap capture path falls back

-- A window whose device context cannot serve the strip (a flip-model swap
-- chain answers black, a windowed client area can clip it) must move to the
-- desktop device context instead of losing the click.
local fallback, fallback_environment, fallback_state = boot(13, {})
local desktop_captures = 0
local window_captures = 0
local original_capture = fallback.capture
fallback.capture = function(x, y, options, width, height, source)
    if source == 'window' then
        window_captures = window_captures + 1
        return nil
    end
    desktop_captures = desktop_captures + 1
    return original_capture(x, y, options, width, height)
end
press(fallback, fallback_environment, 886, 300)
drain(fallback, fallback_environment, 900)
check('an unusable window capture falls back to the desktop', fallback_state.capture_source == 'screen',
    tostring(fallback_state.capture_source))
check('the fallback is counted', (fallback_state.capture_fallbacks or 0) >= 1,
    fallback_state.capture_fallbacks)
check('the click still jumps on the desktop path', #fallback.wheels > 0, #fallback.wheels)
check('the desktop device context is used from then on', desktop_captures >= 1 and window_captures <= 2,
    desktop_captures .. '/' .. window_captures)

-- ------------------------------------------- 14. geometry follows the display

local scaled, scaled_environment, scaled_state = boot({shift = 13, display_height = 2160})
check('a 2160p display scales the geometry', scaled_state.scale == 1.5
    and scaled_state.settings.window == 690 and scaled_state.settings.strip_width == 144
    and scaled_state.settings.cursor_mask_radius == 108,
    tostring(scaled_state.scale) .. '/' .. tostring(scaled_state.settings.window))
check('the display height is reported', scaled_state.display_height == 2160, scaled_state.display_height)
press(scaled, scaled_environment, 886, 300)
drain(scaled, scaled_environment, 1500)
check('a scaled click still lands on the pointer', math.abs(scaled.bar_center() - 300) <= 13,
    scaled.bar_center())
check('a scaled click stays bounded', scaled_state.corrections <= 2, scaled_state.corrections)

-- The same session, moved to a different display: the next press re-derives the
-- geometry and forgets the step and column measured at the old scale.
scaled.state.down = false
tick(scaled, scaled_environment)
scaled_state.pixels_per_notch = 13
scaled.state.bar_cache = nil
scaled.state.display_height = 1440
scaled.state.now = scaled.state.now + 3000
press(scaled, scaled_environment, 886, 520)
check('a display change rescales the geometry', scaled_state.scale == 1
    and scaled_state.settings.window == 460 and scaled_state.settings.cursor_mask_radius == 72,
    tostring(scaled_state.scale) .. '/' .. tostring(scaled_state.settings.window))
check('the old wheel step is dropped with it', scaled_state.pixels_per_notch == nil,
    tostring(scaled_state.pixels_per_notch))

-- ------------------------------------------------- 15. the wide retry pass

-- A thumb outside the normal strip (a long list, or a click far from the thumb)
-- is still found: one doubled retry replaces the empty window.
local retry, retry_environment, retry_state = boot({shift = 13, display_height = 1440})
retry.capture_cap = 2200
retry.state.bar = {left = 880, right = 891, top = 100, bottom = 500}
press(retry, retry_environment, 886, 1000)
drain(retry, retry_environment, 1500)
check('a thumb outside the strip is found by the retry', retry_state.pages == 1 and #retry.wheels > 0,
    'pages=' .. retry_state.pages .. ' wheels=' .. #retry.wheels)
check('the retry is counted', retry_state.wide_retries == 1, tostring(retry_state.wide_retries))

local no_retry, no_retry_environment, no_retry_state = boot({shift = 13, display_height = 1440})
no_retry.capture_cap = 2200
no_retry_state.settings.window_max = no_retry_state.settings.window
no_retry.state.bar = {left = 880, right = 891, top = 100, bottom = 500}
press(no_retry, no_retry_environment, 886, 1000)
drain(no_retry, no_retry_environment, 600)
check('without the retry the same click is a no-op', no_retry_state.pages == 0 and #no_retry.wheels == 0,
    'pages=' .. no_retry_state.pages)

print(string.format('install: %d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
