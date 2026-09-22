# Clickable Scrollbars — v2.6

Adds click-and-drag scrolling to Helldivers 2's native Armory lists for mouse accessibility. Requires **Bingus Shared Loader v15 or newer / API 1**.

## Behavior

- Grabbing a thumb keeps the original grab point under the pointer. Clicking a thumb without moving leaves the list in place.
- Equipment grids and Career use their own native scroll handlers. After grabbing the thumb, the drag follows vertical movement regardless of horizontal position and clamps at either end. Returning from an end uses the same original grab point. No wheel events are sent over tabs or items during these drags.
- Clicking the track centres the thumb there and can continue into a drag.
- Lost window focus, a changed menu/category or a failed native update cancels the gesture. Release and grab again after changing menus. A failed native owner is retired until a different owner is resolved.
- Other detected bars use wheel input. This fallback is quantized by the game's wheel step and pauses outside the scrollbar's column and known vertical bounds. If the full track is unavailable, the observed thumb is the conservative vertical boundary. It cannot provide native pixel-smooth dragging on every menu.
- Fallback track clicks wait until the game has had a frame to consume mouse-up. Queued clicks and corrections are dropped if the pointer or focus leaves their target. Drag notches are never queued for release.

The addon does not move or lock the system pointer. It does not install hooks or patch executable code. Native scrolling uses the game's existing scrollbar, container-position and layout routines; every called entry point must match the supported build.

## Install

Close the game, import **Clickable-Scrollbars-v2.6.zip** into Arsenal or HD2MM, and replace the previous standalone Clickable Scrollbars package. Enable it with Bingus Shared Loader v15+. With Arsenal's default priority, put the loader last, then Purge / Deploy. Use one manager.

If an earlier diagnostic configuration contains `native=0`, remove that override or set `native=1` to use the corrected native path. Do not enable another package containing the same addon alongside this standalone package.

Vanilla Plus Megapack v16 and its Rows variant include this same v2.6 implementation. The bundled version is pinned independently.

## What changed

Career uses a separate scrolling container. The old route could mistake its visible scrollbar for the hidden equipment grid, retire native scrolling, then fall back to the wheel path that pauses outside the track. v2.6 selects the visible owner and gives Career its own direct scroll path.

Equipment updates now cancel an existing scroll animation, call the native thumb setter, and lay out the list. A raw value write skipped the thumb setter's work. Both routes read actual widget transforms and thumb sizes instead of estimating track bounds from a screenshot.

Controller identity uses its numeric address; the game's placeholder text for FFI pointers cannot collapse different owners into one. Regression tests cover large horizontal excursions, both vertical ends, release and menu changes for both routes.

## Settings

Optional file: `%LOCALAPPDATA%\ClickableScrollbars\ClickableScrollbars.ini`. Defaults work without this file. Pixel settings written explicitly remain absolute device pixels. Detection geometry starts from viewport height and adjusts using the measured bar thickness.

| Key | Default | Meaning |
|---|---:|---|
| `enabled` | 1 | 0 disables the addon without uninstalling |
| `scale_geometry` | 1 | 0 keeps the reference 1440p pixels instead of scaling them |
| `window_max` | 1400 | widest the capture strip may grow to in a retry |
| `cursor_mask_radius` | 72 | half-size of the pointer box at the 1440p reference |
| `center_tolerance` | 4 | px of aimed error that counts as centred |
| `jump_max_notches` | 120 | notches a track click may send at once |
| `max_corrections` / `correction_notches` | 2 / 40 | how many settle nudges one click may add, and their size cap |
| `settle_delay_ms` / `settle_interval_ms` / `settle_stable_px` | 200 / 60 / 2 | when and how the thumb is checked after a jump |
| `window` | 460 | px captured above and below the cursor |
| `strip_width` | 96 | px captured across the cursor |
| `narrow_width` / `narrow_window` | 40 / 420 | second pass once a bar column is known |
| `min_height` / `min_width` / `max_width` | 44 / 6 / 28 | accepted thumb size |
| `min_luma` / `max_luma` / `max_spread` | 105 / 220 / 18 | accepted thumb colour |
| `edge_contrast` | 25 | how much darker the track beside a thumb must be |
| `default_pixels_per_notch` / `bar_reference_width` | 13 / 10 | measured wheel step and bar thickness at the reference scale |
| `calibration_samples` | 7 | how many settled observations the median uses |
| `cooldown_ms` | 0 | shortest gap between two track-click jumps |
| `drag_threshold` | 10 | px of vertical movement that starts a wheel-fallback drag |
| `drag_max_step_px` / `drag_max_notches` | 220 / 40 | per-frame guards against a pointer teleport |
| `drag_column_margin` | 2.8 | legacy setting, ignored; wheel dragging stays inside the scrollbar |
| `drag_verify_notches` / `drag_verify_ms` | 3 / 45 | how often a drag re-anchors and checks for a stall |
| `drag_stall_confirmations` | 2 | readings in a row that must show no thumb movement |
| `track_clamp_max_notches` | 12 | notches a learned list end may block before the hint is dropped |
| `native` | 1 | 0 disables direct equipment/Career scrolling and uses the restricted wheel fallback |
| `native_verify_ms` | 200 | how long after a gesture's first write the game's read-back is checked |
| `use_window_capture` | 1 | try the game's own window device context before the desktop one |
| `burst_cache_ms` | 250 | how long a recent measurement may classify a press |
| `burst_capture_every` | 3 | real captures forced after this many answered presses |
| `capture_budget_ms_per_s` | 60 | capture time the addon may spend per second |
| `capture_budget_floor_ms_per_s` | 30 | floor for that budget when frames are slow |
| `probe_step` | 8 | rows between column probes (1 scans every row) |
| `emit_max_notches` | 16 | notches one frame may inject; only track clicks may continue on later frames |
| `log_interval_ms` / `trace_lines` / `trace_events` | 1000 / 48 / 0 | log rate limit, retained decisions, per-emission tracing |
| `error_limit` | 8 | frame errors tolerated before the addon stops |
| `dump_captures` | 0 | write that many capture BMPs next to the log (diagnosis only) |

## Validation and limitations

v2.6 passed offline regression tests and user verification in-game on Steam build **24826606**, EXE **1.8.45317.0**. The release contains the exact runtime source that received that confirmation.

See [validation](docs/VALIDATION.md) for checks and the in-game regression checklist. A passed simulator proves interaction logic against its model, not the game's native ABI. The Windows binding and desktop-capture test passed.

Logs: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ClickableScrollbars.log`. Look for `v2.6`, `native_writes`, `native_ok`, `native_fallbacks`, `errors`, and the final gesture trace. The native owner key ends in `grid` or `career`. Diagnostic image dumps default to off.

## Build

```powershell
python -B scripts/build.py
```

For an environment without an interactive Windows desktop:

```powershell
python -B scripts/build.py --skip-desktop-capture
```

The second command records `desktop_capture_verified=false`; it still runs the detector, runtime, native-model, platform-binding, performance, profiler, simulator, compilation, archive and package checks. Output: `releases/Clickable-Scrollbars-v2.6.zip`.

AI-assisted development with GPT-6 Astra. Helldivers 2 and its assets belong to their respective owners; this is an unofficial mod.
