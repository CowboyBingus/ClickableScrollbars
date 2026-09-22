# v2.10

- Update compatibility for game build 25327279.
- Restore scrollbar track clicks and dragging on updated equipment lists.

# v2.8

- Remove screenshot capture and routine log writes from scrollbar input.
- Batch controller lookups to reduce native reads on ordinary clicks.
- Preserve smooth equipment and Career dragging, sideways movement and tab protection.
- Offline regression checks cover this update; live frame-time verification remains pending.

# v2.7

- Stop screenshot capture and pixel scanning during ordinary clicks or gameplay.
- Keep native equipment and Career dragging, including sideways movement and track clicks.
- Disable routine diagnostic disk writes by default and process input only from update.
- Add regressions requiring zero capture and log work outside supported scrollbars.

# v2.6

- Fix smooth click-and-drag scrolling in equipment and Career menus.
- Keep scrolling when the pointer moves sideways away from the track.
- Prevent dragging across tabs or items from activating them.
- Keep the scrollbar thumb and list aligned, with stable stops at both ends.
- Verify the scrolling fix in-game.

# v2.5

- Corrects the native-grid column offset: the old field was a cache group size
  and rejected valid three-column lists with a group size of nine.
- Restores the native route by default, with an entry-point check for the
  supported solver. A value write runs with the existing layout solver.
- Keeps the grab origin immutable through read-back; fixes temporary FFI wrapper
  identities being mistaken for controller changes. Revalidates the live owner
  and layout before each native drag update.
- A thumb click no longer centres the thumb on release. Native track clicks can
  continue into a drag. Small moves do not require crossing a whole visible row.
- Cancels ownership on focus loss, changed controllers/layouts and failed writes.
  Native failures never switch to wheel input midway through a held gesture.
- Guards every fallback wheel emission, drops input outside its original target,
  waits a frame after mouse-up for track clicks, and never queues drag notches
  for release. Unsupported bars still use quantized wheel scrolling.
- Corrects the simulator so the game cannot drag on behalf of the addon; adds
  regressions for native and fallback gestures and records unavailable desktop
  capture separately from successful offline checks.
- In-game validation of the new candidate remains pending. Older entries below
  describe previous development stages, including superseded approaches.

# v2.4

- Drives the armory list's **own scroll model** instead of synthesising input. The addon
  resolves the live armory item grid from the engine's UI dispatch table (the table the
  shipped Armory mods already read, controller kind 222 at `game.dll+0x276CB80`, grid at
  controller `+523752`) and reads the state the game itself uses: content height
  (`grid+600424`), scrollable span (`grid+0x8C0`), the scrollbar's value (`grid+0x8C8`),
  the pixel offset the game derives from them (`grid+600416 = span * value`), the visible
  item range (`grid+622656/622660`) and the row/column layout (`grid+597772`, `+602088`).
- A press on the bar becomes a real scrollbar drag: the value follows the pointer for as
  long as the button is held, so the thumb moves by exactly the distance the pointer
  moved, with no wheel notch, no scheduling queue and no synthetic input anywhere. A
  press beside the bar writes the value once, which is the native page jump.
- The bar's track is reconstructed from one measured thumb plus the model (the thumb is
  `viewport / content` of the track and sits `value` of the way along what a drag can
  move it), so the mapping is derived from the game's own numbers rather than from
  display-height guesses.
- Every native read is bounds-checked against the ranges the offsets were measured under
  (rows, columns, item count, content, span, value). A build whose grid does not match is
  refused before anything is written, and the wheel path takes over.
- A write is verified once per gesture (`native_verify_ms`, default 200 ms) against the
  game's read-back: value, visible range or pixel offset. A gesture the game does not
  answer retires the native route for the session and logs `native retired`, so the
  addon can never leave the bar dead.
- The wheel design stays exactly as it was for everything else, and is now explicitly the
  fallback: the strip detector, the burst model, the settle corrections and the drag
  follow are unchanged when the native grid is not reachable.
- Adds `tests/test_native.lua`: 28 checks over a synthetic model of the live grid
  (dispatch resolution, bounds, viewport derivation, track reconstruction, click aim,
  drag mapping, clamping, both writes, refusal cases, movement detection, malformed
  grids, unregistered grid).
- Documents what changed in the addon's own claims: this build performs **data writes**
  into the game's UI state (the same class of write the shipped Armory Preview Cache mod
  performs on its widgets). It still ships no DLL, patches no code, installs no hook,
  loads no library and never touches executable memory.
- **Fixes "clicking and dragging does literally nothing" (first v2.4 report).** Two
  faults, both now covered: the grid was resolved once and remembered, but the Armory
  rebuilds its controller - and with it the grid - every time the screen is entered, so
  the addon kept writing into an object no screen owned; the grid is now resolved from
  the dispatch table on every press. And when a native attempt was not answered, the
  gesture was left inert: a press on the bar does nothing if the native route is out
  *and* the loader-provided UI bridge is absent, which is the case in game. A bar press
  now always arms the wheel drag underneath the native attempt, and a failed
  verification hands the *same* gesture over to it (and a page click over to the wheel
  jump) instead of eating it.
- Verifies the native write against the fields the *game* derives - first/last visible
  item and the solver's published anchor - never against the value and pixel offset the
  addon itself wrote, which is what made the first build report `native_ok` while the
  list never moved.
- **The bar works again (second v2.4 report).** The deployed build was byte-identical to
  the build that was announced, and its log says why nothing moved: `native_ok=0` after
  ten writes (the engine never re-solved its visible range from the value), and
  `ui_pending=6`, because a press on the bar still fell into the loader-bridge branch
  once the native route retired - the bridge is not present in game, so the gesture had
  no actuator at all. The wheel drag is now armed for every bar press whenever the
  native route is not driving, with or without a bridge; the harnesses assert the
  restored contract (a held thumb drags, the release ends the drag).
- **The native path now asks the game to re-solve.** A bare value write leaves the
  visible range exactly where it was, so the write is followed by the rebuild flag and
  by the grid's own solver (`game.dll+0x1622850`, the routine that turns the pixel
  offset into the visible range) - the same class of native call the shipped Armory
  mods already make, wrapped in `pcall` and reported rather than retried.
- The log header now carries the build it came from (`v2.4`).

# v2.3
- The thumb of these scrollbars is the game's own control: the shipped Armory template styles it with an `IsDragging` state and no page buttons exist, so the engine already drags it natively with a real pointer capture. The addon no longer synthesises a drag at all (the log records `thumb_native`), which is what used to activate the tabs and the list items: a wheel that arrives while the left button is held presses whatever is under the pointer.
- Keeps the track click, which is the part the game leaves inert: a press beside the thumb aims it under the pointer and sends the wheel notches the game needs to get there.
- Sends a click's notches on the frame after the mouse-up, so no injected notch ever arrives while the button is held and nothing else can be pressed by a click.
- Caps a frame at `emit_max_notches` (16) and carries the rest into the following frames, so no single frame can flood the game's input queue.
- Adds `tests/test_ui_sim.lua`: it models the game -- measured layout including the Q/E and Z/C hit boxes, an animated and clamping list, the wheel hit-tested where the pointer is and re-read as a press while the button is held, and the thumb's own native drag. It asserts that the addon injects nothing during a hold, that the list follows the hand (1.00x) and the randomised drags stay exact, that both ends are reached and pulled back from, and that no scenario activates a widget.
- Fixes the crash reported on v2.2: `platform.display_height` referenced the shared `rect` scratch buffer that was declared further down the platform, so the reference was a global. It is now declared before every function that uses it, and the platform test lints every `ffi.new` buffer for that ordering.
- A display query that still fails (a driver or Windows quirk) is caught and counted as `geometry_failures`, so the addon keeps working at the reference scale instead of stopping after `error_limit` frames.
- Answers a press from the geometry the last capture measured when the press is on the same bar, so spam clicking no longer captures an image on every click.
- Forces a real capture every `burst_capture_every` presses once notches have been sent, and re-anchors whenever the display geometry changes, so the model cannot drift.
- Limits the addon to `capture_budget_ms_per_s` of capture time per second: a click that would exceed it is dropped rather than stalling the game's frame.
- Widens the capture window only when the press landed on panel-dark pixels, so clicking list artwork costs one capture instead of two.
- Scans only the columns that can hold a thumb (`probe_step`), which cuts the pixel scan of a wide strip by roughly five times and leaves the accepted bars identical.
- Reuses the brightness the capture already measured instead of sampling the strip twice per analysis.
- Adds the `probe_step`, `burst_cache_ms`, `burst_capture_every` and `capture_budget_ms_per_s` settings and logs `burst_skips`, `budget_skips` and `capture_ms_per_s`.
- Adds `tests/test_performance.lua`, a synthetic spam-clicking benchmark with a capture and pixel cost model, which reports worst frame time, captures per press and the addon's share of frame time.
- Adds `tests/test_profile.lua`, a local profiler: it times the detector and the runtime frame body on synthetic scenes, fuzzes 3000 samples plus hostile settings and degenerate captures, and loads the module into a sandbox that records unknown global reads so a typo'd local cannot ship unnoticed.
- Rejects bar-like columns that have no panel in them, which removes the one screen shape that used to cost five times a normal analysis (bright vertical stripes: 772 us to 138 us).
- Bounds how many columns one pass may fully scan, preferring the pointer's own column, so no screen content can make the pixel scan unbounded.
- Treats a malformed cursor as `no_cursor` and a missing mask as no mask instead of raising.
- Caps the notches a single frame may inject (`emit_max_notches`, counted as `emit_clamps`), so a pathological jump cannot spend the frame in the input queue.
- Flags a thumb run cut off by the edge of the capture as clipped, so the centre is inferred from the tracked height instead of biased by up to half the missing length.
- Accepts a jump whose first settle reading shows the thumb arrived where the model predicted and no whole wheel step could improve, which halves (or better) the captures a jump spends and removes a correction it did not need.
- Halves the default capture budget (`capture_budget_ms_per_s` 120 to 60) and scales it down with the measured frame interval on a machine that is already struggling, with `capture_budget_floor_ms_per_s` as the floor.
- Rations the settle verification through the same budget as a press, so a machine that has spent its share leaves a jump unverified (`settle_budget_skips`) instead of stalling the frame it just scrolled.
- Leaves a cheap capture path unthrottled: with the game's own window device context a capture costs about a microsecond, so the budget never bites and every press is answered.
- Logs `game_fps`, `budget_effective` and `capture_share_pct`, so the cost of captures on a given machine is visible without guessing.
- Sends a click's notches one frame *after* the release instead of while the button is held. While a press is held the game re-reads the widget under the pointer for every injected notch, which is how a click could activate whatever the pointer had reached; with the release first, nothing can be activated and the list still scrolls.
- Caps a frame at `emit_max_notches` (16, was 240) and carries the rest into the following frames, so no single frame can flood the game's input queue with injected events.
- Expresses the sideways band in widths of the bar rather than display pixels (`drag_column_margin` 3.6 towards the list, `drag_column_margin_outer` 0.1 away from it, `bar_reference_width` 10), and reads which side the list is on from the pixels beside the bar (`content_side`). The live Armory frame has its artwork, spine and track groove to the left of a 10 px bar with 41 px of empty gutter, which is what the 3.6 comes from.
- Scales the interface from the bar's measured thickness instead of the viewport height, and the wheel-step seed with it: the live machine showed the same 10 px bar, at the same screen column, and the same 13 px/notch wheel step, with a 1440 px client and a 998 px one -- so the display height was seeding a drag 1.44x too fast. The measurement is kept within a factor of two of the height guess (`ui_ruler` in the log), dropped when the display changes, and can only ever *shrink* the capture windows: a false bar-like run of the wrong thickness must not be able to widen them.
- Retries a press once with half the pointer box when a bar-like run was seen but the box left too little of it to judge (`mask_retries`), which is what happens when the interface is smaller than the guessed scale. An ordinary missed click still costs a single capture.
- Fixes the v2.3 beta report "the scrollbar works for a little bit then breaks completely": the log showed `drag_limits=112` with no learned track end, and the clamped frames were the stall pause -- 400 ms doubling while the pointer kept pushing, with the reversal that used to clear it lost when the pause replaced the old per-direction stall. Holds now replace the pause entirely.
- Adds `tests/test_ui_sim.lua`: a model of the game -- measured layout, animated and clamped list, one wheel notch moving the thumb 13 px, the Q/E and Z/C strips with their measured hit boxes, and the reported rule that an injected wheel re-reads the widget under the pointer -- driven by the real addon. It reproduces what the live reports showed: a fast drag drifting 33 px left used to press Q/E and Z/C, and randomised drags lost up to 286 px. It now asserts that the thumb follows the pointer, that both ends are reached and pulled back from, that 60 randomised jittery drags stay within a few px, that three UI scales track, that a click sends nothing while the button is held, and that no scenario ever activates a widget.
- Injects nothing at all while another window has focus: a drag pauses (and re-baselines when the game comes back) and a pending settle verification is dropped rather than sending wheel input to whatever window is in front.
- Scales `probe_step` with the display like the other pixel constants.

# v2.2

- Scales the capture window, the pointer box, the accepted bar size, the drag thresholds and the wheel-step seed to the display height instead of keeping fixed pixels.
- Keeps the tested 1440p values exactly as the reference, so an existing install behaves identically.
- Follows a resolution or monitor change on the next press and re-learns the wheel step for the new scale.
- Retries once with a doubled capture window when a thumb is taller than the strip or the click is far from it, instead of losing the click.
- Leaves values set in the ini absolute: a number typed by hand means exactly that number.
- Adds the `window_max`, `scale_geometry` and `cursor_mask_radius` settings and logs `scale`, `display_height` and `wide_retries`.

# v2.1

- Sends every wheel notch on the frame the pointer produced it, so the thumb can no longer trail the mouse or keep moving after it stops.
- Removes the paced emission queue that caused the lag and the independent pacing.
- Stops capturing pixels while a drag is in progress.
- Runs the settle pass only after the thumb has stopped moving, and only when a whole notch is predicted to reduce the measured error.
- Accepts a landing inside half a wheel notch instead of nudging it, which stops the overshoot-and-jump-back seen after a click.
- Limits a click to the burst plus `max_corrections` corrections, each of which must shrink the error.
- Reports `no_response` when a multi-notch jump produced no movement at all, instead of chasing the list end.
- Bridges only unreadable pixels inside the pointer's sprite box, so a thumb under the pointer keeps its real extent.
- Reconstructs a hidden thumb end from the tracked thumb height instead of rejecting the press.
- Learns the wheel step as the median of settled observations only.
- Prefers the game's own window device context for captures, with a validated fallback to the desktop device context.
- Logs the settings in force, counters, timing health, the tracked thumb, the calibration samples, the reason tally and the last 48 decisions.
- Keeps running after a single bad frame, counts it and stops only after `error_limit` failures.
- Adds the `error_limit`, `use_window_capture`, `log_interval_ms`, `calibration_*`, `max_corrections`, `settle_*` and `drag_max_*` settings; removes the old queue and page settings.

# v2

- Reimplements the mod as a Bingus Shared Loader addon after a shipped XAML template override was verified ineffective in game.
- Locates the native scrollbar thumb in a captured strip of the rendered frame.
- Clicks on the invisible track move the thumb to the cursor; presses on the thumb grab it instead of jumping.
- Injects wheel notches with `SendInput`, the scroll path the game already implements.
- Injects nothing when the click lands on list content.
- Writes one log file under `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs` and no capture images unless `dump_captures` is set.
- Removes the low-level mouse hook entirely; input comes only from Lua frame polling.

# v1

- Adds page buttons to the shipped XAML scrollbar templates.
- Deploys and loads correctly but has no visible effect, because the item-select lists draw their scrollbars in native UI.
