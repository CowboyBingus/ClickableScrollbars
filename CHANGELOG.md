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
