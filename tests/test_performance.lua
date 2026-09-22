-- Synthetic spam-clicking benchmark: captures and pixel scans are charged to a
-- frame clock. A regression that captures on every press shows up as a worst frame
-- far beyond the budget. Cost model: docs/RESEARCH.md.

package.path = (arg and arg[1] or '.') .. '/?.lua;' .. package.path

rawset(_G, '__CLICKABLE_SCROLLBARS_TEST', true)
local module = assert(loadfile((arg and arg[2]) or 'ClickableScrollbars/src/clickable_scrollbars.lua'))()

local CAPTURE_COST_MS = tonumber(arg and arg[3]) or 9
local PIXEL_COST_MS = tonumber(arg and arg[4]) or 0.00006
local FRAME_MS = 1000 / 60

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
    local platform = {wheels = {}, captures = 0, capture_ms = 0}
    platform.state = {
        now = 1000, cursor = {x = 900, y = 700}, down = false, foreground = true,
        bar = {left = 880, right = 889, top = 460, bottom = 700}, shift = 13,
        display_height = options.display_height or 1440,
        -- A zone of bright, high-frequency content: alternating 200/60 pixels
        -- look like list artwork, not like the flat panel behind a bar. It sits
        -- clear of the bar's own columns so it never changes that bar's edges.
        noise = {left = 700, right = 860, top = 200, bottom = 1400},
    }
    function platform.now() return platform.state.now end
    function platform.cursor() return platform.state.cursor.x, platform.state.cursor.y end
    function platform.pressed() return platform.state.down end
    function platform.key_state() return 0 end
    function platform.foreground_self() return platform.state.foreground end
    function platform.display_height() return platform.state.display_height end
    function platform.close() end
    function platform.wheel(notches)
        platform.wheels[#platform.wheels + 1] = notches
        local bar = platform.state.bar
        local step = platform.state.shift * (notches > 0 and -1 or 1)
        bar.top, bar.bottom = bar.top + step, bar.bottom + step
        return true
    end
    function platform.capture(center_x, center_y, options, strip_width, strip_window)
        -- Charge the copy and the scan to the frame clock, exactly like the real
        -- call blocks the game thread.
        platform.captures = platform.captures + 1
        local width = math.min(strip_width or options.strip_width, 240)
        local height = math.min((strip_window or options.window) * 2, 4000)
        local cost = (platform.capture_cost_ms or CAPTURE_COST_MS) + width * height * PIXEL_COST_MS
        platform.capture_ms = platform.capture_ms + cost
        platform.state.now = platform.state.now + math.floor(cost + 0.5)
        local origin_x = center_x - math.floor(width / 2)
        local origin_y = center_y - math.floor(height / 2)
        local bar = platform.state.bar
        local noise = platform.state.noise
        local function rgb(x, y)
            local screen_x, screen_y = origin_x + x, origin_y + y
            if screen_x >= bar.left and screen_x <= bar.right
                and screen_y >= bar.top and screen_y <= bar.bottom then
                return 149, 149, 149
            end
            if noise and screen_x >= noise.left and screen_x <= noise.right
                and screen_y >= noise.top and screen_y <= noise.bottom
                and (screen_x + screen_y) % 2 == 0 then
                return 200, 200, 200
            end
            return 45, 45, 45
        end
        return {width = width, height = height, origin_x = origin_x, origin_y = origin_y, rgb = rgb}
    end
    return platform
end

local function boot(options)
    local platform = new_platform(options or {})
    local environment = {update = function() end, shutdown = function() end,
                         CowboyBingusModLoader = {api = 1, open_log = function() return nil end}}
    local state = module.install(function() return platform end, environment)
    platform.environment = environment
    platform.state_object = state
    return platform, environment, state
end

local function tick(platform, milliseconds)
    -- Returns the frame time the addon consumed in this frame, so a settle
    -- capture that lands between clicks is measured too.
    local before = platform.state.now
    platform.state.now = platform.state.now + milliseconds
    platform.environment.update(0.016)
    return platform.state.now - before - milliseconds
end

-- One spam click, returning the frame time the addon spent inside the press frame
-- and the release frame that follows it (a click's notches go out on the release).
local function click(platform, x, y)
    platform.state.down = false
    local release = tick(platform, 1)
    platform.state.cursor = {x = x, y = y}
    platform.state.now = platform.state.now + 1
    local before = platform.state.now
    platform.state.down = true
    platform.environment.update(0.016)
    local press = platform.state.now - before + release
    platform.state.down = false
    platform.state.now = platform.state.now + 1
    local after = platform.state.now
    platform.environment.update(0.016)
    return press + platform.state.now - after - 1
end

-- One anchoring press and a settle, then `clicks` spam clicks at the same spot
-- with a 60 fps frame between them. Returns the platform, the state, the worst
-- press frame, the total addon time and the number of captures the burst took.
local function run_burst(clicks, x, y, tweak)
    local platform, environment, state = boot(nil)
    if tweak then tweak(state) end
    click(platform, x, y)
    for _ = 1, 40 do tick(platform, FRAME_MS) end
    local captures_before = platform.captures
    local worst, total = 0, 0
    for _ = 1, clicks do
        local busy = click(platform, x, y) + tick(platform, FRAME_MS)
        worst = math.max(worst, busy)
        total = total + busy
    end
    for _ = 1, 40 do tick(platform, FRAME_MS) end
    environment.shutdown()
    return platform, state, worst, total, platform.captures - captures_before
end

local CLICKS = 120
local FRAME_BUDGET = CLICKS * FRAME_MS

-- 1. Hammering one spot on the bar: the first press anchors the model and the
--    rest are grabs of the same geometry, so they must cost nothing at all.
local grab, grab_state, grab_worst, grab_total, grab_captures = run_burst(CLICKS, 886, 600)
print(string.format('grab spam %3d clicks: captures=%3d burst_skips=%3d budget_skips=%3d worst_press_frame=%.1f ms '
    .. 'addon_time=%.1f ms (%.1f%% of %.0f ms of frames) capture_ms=%d',
    CLICKS, grab_captures, grab_state.burst_skips or 0, grab_state.budget_skips or 0, grab_worst, grab_total,
    100 * grab_total / FRAME_BUDGET, FRAME_BUDGET, grab.capture_ms or 0))
check('a grab burst does not capture per press', grab_captures <= CLICKS / 8, grab_captures .. ' of ' .. CLICKS)
check('the burst model answers nearly every press',
    (grab_state.burst_skips or 0) >= CLICKS - grab_captures - 2, grab_state.burst_skips or 0)
check('no press frame stalls on a capture', grab_worst <= 2 * CAPTURE_COST_MS, string.format('%.1f ms', grab_worst))
check('a grab burst stays inside the capture budget', grab.capture_ms <= 150, grab.capture_ms .. ' ms')
-- A grab arms the drag, and a click on the thumb nudges its centre under the
-- pointer: a couple of notches at most, never a page.
check('grabbing scrolls at most a centring nudge', #grab.wheels <= 4,
    tostring(#grab.wheels) .. ' wheels')

-- 2. The same burst with the burst model disabled is what a regression looks
--    like: the guards have to drop most of the presses to stay inside the frame
--    budget, so the menu stops answering the player.
local slow, slow_state, slow_worst, slow_total = run_burst(CLICKS, 886, 600, function(state)
    state.settings.burst_cache_ms = 0
    state.base_settings.burst_cache_ms = 0
end)
print(string.format('grab spam %3d clicks without the model: captures=%3d worst_press_frame=%.1f ms '
    .. 'addon_time=%.1f ms (%.1f%%) dropped=%d', CLICKS, slow.captures, slow_worst, slow_total,
    100 * slow_total / FRAME_BUDGET, slow_state.skipped))
check('with the burst model every grab press is answered',
    grab_state.skipped == 0 and grab_state.misses == 0,
    tostring(grab_state.skipped) .. '/' .. tostring(grab_state.misses))
check('without the model the guards must drop the spam', (slow_state.skipped or 0) >= CLICKS / 2,
    slow_state.skipped or 0)
-- A click's captures now land on the release frame it is answered on, so the same
-- work shows up as roughly half the ms it used to; the guards are what cap it.
check('without the model the addon spends real frame time', slow_total > 40,
    string.format('%.1f ms', slow_total))
check('the burst model is a large win in answered presses',
    (slow_state.skipped or 0) > (grab_state.skipped or 0) + 100,
    tostring(slow_state.skipped) .. ' vs ' .. tostring(grab_state.skipped))

-- 3. Spam clicking bright list artwork: the click pixel is content, so the first
--    pass refuses it and the panel-dark widening pass must not run.
local content, content_environment, content_state = boot({})
content.state.bar = {left = 3000, right = 3010, top = 3000, bottom = 3010}
local content_captures = 0
local content_worst, content_total = 0, 0
for _ = 1, 60 do
    local busy = click(content, 800, 700) + tick(content, FRAME_MS)   -- inside the artwork zone
    content_worst, content_total = math.max(content_worst, busy), content_total + busy
end
for _ = 1, 40 do tick(content, FRAME_MS) end
content_captures = content.captures
content_environment.shutdown()
print(string.format('content spam 60 clicks: captures=%d (%.2f per press) worst_press_frame=%.1f ms '
    .. 'addon_time=%.1f ms refused=%d rate_limited=%d', content_captures, content_captures / 60, content_worst,
    content_total, content_state.misses, content_state.skipped))
check('a bright content click costs one capture and no widening', content_captures <= 30, content_captures)
check('content clicks are refused, not scrolled', content_state.misses >= 6 and #content.wheels == 0,
    tostring(content_state.misses) .. ' misses, ' .. tostring(#content.wheels) .. ' wheels')
check('the click rate is limited, not queued', content_state.skipped >= 20, content_state.skipped)

-- 4. Spam clicking dark panel with no bar anywhere: this is the legitimate
--    expensive path (it widens once), and the per-second budget must hold.
local panel, panel_environment, panel_state = boot({})
panel.state.bar = {left = 3000, right = 3010, top = 3000, bottom = 3010}
panel.state.noise = nil
local panel_start = panel.state.now
local panel_busy = 0
for _ = 1, 60 do
    local busy = click(panel, 886, 700) + tick(panel, FRAME_MS)
    if busy > 0 then panel_busy = panel_busy + busy end
end
for _ = 1, 40 do tick(panel, FRAME_MS) end
local panel_elapsed = (panel.state.now - panel_start) / 1000
panel_environment.shutdown()
print(string.format('panel spam 60 clicks: captures=%d (%.2f per press) budget_skips=%d capture_ms=%d over '
    .. '%.2f s (%.1f%% of wall time) addon_time=%.1f ms', panel.captures, panel.captures / 60,
    panel_state.budget_skips or 0, panel.capture_ms, panel_elapsed,
    100 * panel.capture_ms / (panel_elapsed * 1000),
    panel_busy))
check('dark panel spam widens at most once per press', panel.captures <= 2 * 60 + 2, panel.captures)
check('the per-second capture budget is enforced', (panel_state.budget_skips or 0) >= 1,
    panel_state.budget_skips or 0)
check('capture time stays inside the budget', panel.capture_ms <= 2.5 * 120 + 2 * CAPTURE_COST_MS,
    panel.capture_ms .. ' ms')

-- 5. A track click far from the thumb: the widened pass is what makes it work.
local far, far_environment, far_state = boot({})
far.state.bar = {left = 880, right = 889, top = 100, bottom = 500}
far.capture_cap = 4000
far.state.cursor = {x = 886, y = 1200}
local far_worst, far_total, far_captures = 0, 0, 0
for _ = 1, 30 do
    local busy = click(far, 886, 1200) + tick(far, FRAME_MS)
    far_worst, far_total = math.max(far_worst, busy), far_total + busy
    far_captures = far_captures + 1
end
for _ = 1, 40 do tick(far, FRAME_MS) end
far_environment.shutdown()
print(string.format('far track click: wide_retries=%d pages=%d wheels=%d worst_press_frame=%.1f ms',
    far_state.wide_retries or 0, far_state.pages, #far.wheels, far_worst))
check('a far track click still lands', far_state.pages >= 1 and #far.wheels > 0,
    'pages=' .. tostring(far_state.pages))
check('the widened pass is counted', (far_state.wide_retries or 0) >= 1, tostring(far_state.wide_retries))

-- 6. Spam clicking that keeps moving the thumb forces the model to re-anchor:
--    the captures that cost must be a fraction of the presses, never all of them.
local moving, moving_environment, moving_state = boot({})
local moving_worst, moving_total = 0, 0
for index = 1, 90 do
    -- Alternate above and below the thumb so every press is a track click and
    -- every jump moves the bar again.
    local busy = click(moving, 886, index % 2 == 0 and 300 or 900) + tick(moving, FRAME_MS)
    moving_worst, moving_total = math.max(moving_worst, busy), moving_total + busy
end
for _ = 1, 40 do tick(moving, FRAME_MS) end
moving_environment.shutdown()
print(string.format('moving-thumb spam 90 clicks: captures=%d (%.2f per press) pages=%d burst_skips=%d '
    .. 'worst_press_frame=%.1f ms capture_ms=%d', moving.captures, moving.captures / 90, moving_state.pages,
    moving_state.burst_skips or 0, moving_worst, moving.capture_ms or 0))
check('a moving-thumb burst captures a fraction of the presses', moving.captures <= 90 / 2 + 4,
    moving.captures .. ' of 90')
check('a moving-thumb burst still scrolls', moving_state.pages >= 20, moving_state.pages)
check('a moving-thumb burst stays inside the budget', moving.capture_ms <= 2.5 * 120 + 4 * CAPTURE_COST_MS,
    moving.capture_ms .. ' ms')

-- 7. A well-aimed jump must verify itself with a single capture: the settle's
--    first observation shows the thumb arrived where the model predicted, which
--    is proof it has stopped, so the second reading is wasted work.
local settle, settle_environment, settle_state = boot(nil)
click(settle, 886, 600)                                   -- grab, and learn the bar
for _ = 1, 40 do tick(settle, FRAME_MS) end
settle_state.pixels_per_notch = 13                        -- a calibrated step
click(settle, 886, 900)                                   -- a track click below the thumb
local after_press = settle.captures
for _ = 1, 60 do tick(settle, FRAME_MS) end
local settle_captures = settle.captures - after_press
print(string.format('well-aimed jump: settle captures=%d pages=%d corrections=%d reason=%s',
    settle_captures, settle_state.pages, settle_state.corrections, tostring(settle_state.last_reason)))
check('a well-aimed jump is verified with one capture', settle_captures <= 1, settle_captures)
local settle_centre = (settle.state.bar.top + settle.state.bar.bottom) / 2
check('the jump still lands', math.abs(settle_centre - 900) <= 13, settle_centre)

-- 8. The budget is a share of frame time, so a slow machine gets less of it.

-- A cheap capture path (the game's own window DC): ten clicks a second all get
-- processed, because each capture costs almost nothing against the budget.
local cheap, cheap_environment, cheap_state = boot(nil)
cheap.capture_cost_ms = 0.001
local cheap_presses = 0
for _ = 1, 40 do
    click(cheap, 886, 600)
    tick(cheap, FRAME_MS)
    cheap_presses = cheap_presses + 1
end
for _ = 1, 40 do tick(cheap, FRAME_MS) end
cheap_environment.shutdown()
print(string.format('cheap capture path: %d presses, captures=%d budget_skips=%d capture_ms=%.2f',
    cheap_presses, cheap.captures, cheap_state.budget_skips or 0, cheap.capture_ms))
check('a cheap capture path is never throttled', (cheap_state.budget_skips or 0) == 0
    and cheap_state.skipped == 0, tostring(cheap_state.budget_skips) .. '/' .. tostring(cheap_state.skipped))

-- A slow machine: 30 fps frames must shrink the effective budget, and an
-- exhausted budget must skip the settle rather than stalling the frame.
local slow_machine, slow_machine_environment, slow_machine_state = boot(nil)
for _ = 1, 60 do tick(slow_machine, 33) end
local effective = slow_machine_state.effective_budget_ms_per_s or 0
print(string.format('slow frames: game_fps=%.0f effective_budget=%.0f ms/s',
    1000 / (slow_machine_state.frame_interval_ms or 33), effective))
check('a slow machine gets a smaller budget', effective > 0 and effective < 60,
    tostring(effective))
check('the budget never falls below its floor', effective >= 30, tostring(effective))

local settler, settler_environment, settler_state = boot(nil)
settler_state.settings.capture_budget_ms_per_s = 12
settler_state.settings.capture_budget_floor_ms_per_s = 12
settler_state.pixels_per_notch = 13
click(settler, 886, 600)                       -- anchor: one capture spends the window
for _ = 1, 60 do tick(settler, 33) end         -- two seconds: the next window is fresh
click(settler, 886, 900)                       -- a track click: its capture spends it again
for _ = 1, 60 do tick(settler, 33) end         -- the settle now has nothing left
settler_environment.shutdown()
print(string.format('tiny budget: capture_ms=%.1f budget_skips=%d settle_budget_skips=%d pages=%d',
    settler.capture_ms, settler_state.budget_skips or 0, settler_state.settle_budget_skips or 0,
    settler_state.pages))
check('the jump still happened', settler_state.pages >= 1, settler_state.pages)
check('the settle is rationed by the same budget', (settler_state.settle_budget_skips or 0) >= 1,
    tostring(settler_state.settle_budget_skips))
check('the budget holds even when settles want captures', settler.capture_ms <= 12 * 2 + 40,
    string.format('%.1f ms', settler.capture_ms))

-- 9. The column probe must not change what the detector accepts, and the new
--    settings must be reachable from the ini.
local function synthetic(step)
    local options = module.parse_settings(nil, nil)
    options.probe_step = step
    local function rgb(x, y)
        if x >= 30 and x <= 41 and y >= 60 and y <= 300 then return 149, 149, 149 end
        return 45, 45, 45
    end
    local sample = {width = 80, height = 400, origin_x = 0, origin_y = 0, rgb = rgb}
    local bar = module.find_thumb(sample, {x = 36, y = 380}, options)
    return bar and (bar.top .. '..' .. bar.bottom) or 'nil'
end
check('the column probe finds the same bar', synthetic(1) == synthetic(8) and synthetic(8) == '60..300',
    synthetic(1) .. ' vs ' .. synthetic(8))
check('probing can be disabled', module.parse_settings('probe_step=1\n', nil).probe_step == 1)
check('the burst model can be disabled', module.parse_settings('burst_cache_ms=0\n', nil).burst_cache_ms == 0)
check('the budget can be disabled', module.parse_settings('capture_budget_ms_per_s=0\n', nil)
    .capture_budget_ms_per_s == 0)
check('the new settings are clamped',
    module.parse_settings('probe_step=0\n', nil).probe_step == 1
    and module.parse_settings('burst_capture_every=0\n', nil).burst_capture_every == 1
    and module.parse_settings('capture_budget_ms_per_s=99999\n', nil).capture_budget_ms_per_s == 5000)

print(string.format('performance: %d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
