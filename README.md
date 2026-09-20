# Clickable Scrollbars

Lets you drive the item-select menu scrollbars with the mouse instead of only
being able to use the mouse wheel.

- **Click the track to jump there.** One click beside the bar sends the whole
  move at once, so the thumb glides to the pointer instead of stepping towards
  it. Its centre stops within half a wheel notch of the cursor, which is the
  finest a whole wheel notch can aim.
- **Press the bar to drag it.** Pressing the bar itself never jumps — it only
  grabs the bar, and the thumb then moves by exactly the same distance as your
  mouse, on the frame you move it. There is no queue and no schedule, so the
  bar cannot lag behind the hand or keep moving after it stops.
- **Nothing is re-aimed behind your back.** The verification pass after a click
  runs only once the thumb has stopped moving, it keeps at most `max_corrections`
  nudges per click, and each nudge must be smaller than the error it removes, so
  a click cannot end in a visible back-and-forth.
- The wheel, controller navigation and every other menu interaction stay as they
  were.
- **No files on disk beyond the log.** Diagnostic capture dumps are off by
  default (`dump_captures=0`).
- **Fits your display.** The capture window, pointer box, accepted bar size and
  drag thresholds scale with the viewport height from a tested 1440p reference,
  so 1080p, 1440p and 4K screens get the same relative geometry. A resolution or
  monitor change is picked up on the next click.
- **Covers the Armory lists.** Primary, Secondary, Throwable, Armor, Helmet,
  Cape, Emote, Victory Pose, Player Card, Title and the Career stats list — the
  lists whose bars the game draws in its native UI, where the shipped XAML
  templates cannot reach (see the research document).
- **Loader-based.** A Bingus Shared Loader addon: no DLL, no executable-memory
  patch, no game-file override.

## Loader-only guarantees

This addon is a plaintext Lua resource that the mod loader discovers through its
`-- HD2-Addon:` declaration. It ships no DLL, does not patch or write game
memory, installs no system hooks and never touches a game file. At runtime it
only reads pixels (`BitBlt`), polls the left button (`GetAsyncKeyState`) and
injects wheel events (`SendInput`) from inside the running game. The build
refuses to package a script that mentions hook, DLL-loading or memory-mutation
APIs, and the package test asserts the shipped payload is free of them.

Install it through HDArsenal or HD2MM, never by copying files into the game
directory yourself: managers own the deployment and the load order.

## How it works

The game's Armory scrollbars are native widgets: a uniform grey thumb, 9–14 px
wide, with the track invisible and inert. The addon watches the left mouse
button, captures a narrow strip of the rendered frame around the cursor, and
recognises that thumb:

1. Vertical runs of neutral grey pixels (brightness window, channel spread and
   uniformity checks) are merged into candidate thumbs. The pointer is drawn as
   a coloured sprite about 100 px across with a bright core and a mild neutral
   halo; inside its box a pixel that is coloured or too bright to judge is
   treated as hidden and bridged, while a pixel that still reads as dark panel
   ends the run. A bar under the pointer therefore keeps its real extent
   instead of being eaten by the mask.
2. A candidate whose column holds the cursor is kept only when the background
   beside it is clearly darker (edges) and the click pixel itself is dark (the
   invisible track, not list content).
3. A track click sends the whole distance at once (up to `jump_max_notches`).
   The verification pass then runs only when the thumb has stopped, and only
   when a whole notch is predicted to reduce the remaining error; if the game
   did not move at all for a multi-notch burst, the list is at its end (or the
   wheel was ignored) and the pass stops instead of nudging again.
4. A drag converts mouse movement into wheel notches one-to-one using the
   learned wheel step, and sends them on the frame that produced them.
5. The wheel step is the median of the displacements the game actually
   produced, learned only from settled measurements, so both the jump and the
   drag mapping get more accurate as you use them.
6. Thumb ends hidden by the pointer sprite are reconstructed from the tracked
   thumb height, so a press on or beside a partly hidden bar is still classified
   correctly rather than read as list content.
7. Cost is bounded: nothing is captured while a drag is in progress, the first
   click in a menu scans a wide strip and later clicks re-check only the known
   bar column (40 px wide), and the capture itself prefers the game's own window
   device context — measured at 0.2 ms against 9 ms for the desktop device
   context at 3440×1440 — falling back to the desktop context (and logging the
   choice) when a window copy comes back black or clipped.

8. Geometry is relative to the display: the pixel constants were measured on a
   1440 px tall viewport and are multiplied by `display_height / 1440`, so a
   2160p screen gets a 690 px capture window, a ±108 pointer box and a 42 px
   bar-width limit. If a thumb still does not fit in the strip, one doubled
   retry finds it rather than losing the click. Numbers written in the ini are
   absolute device pixels and are never scaled.

Every decision is written to
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ClickableScrollbars.log`: the
settings in force, counters, timing health (`capture_ms_avg`, `frame_ms_avg`,
`capture_source`), the tracked thumb, the calibration samples, a tally of every
decision reason and the last 48 decisions with millisecond stamps. The log is
rewritten in place and rate limited, so it is the only file the addon touches.

Background: [why the shipped scrollbar templates cannot reach these bars, and
what the input-level design does instead](docs/RESEARCH.md) ·
[what has been verified](docs/VALIDATION.md).

## Install

Close the game, import `Clickable-Scrollbars-v2.2.zip` into HDArsenal or HD2MM
alongside **Bingus Shared Loader v15 or newer**, enable both, then purge and
redeploy. The loader discovers the addon through its `-- HD2-Addon:`
declaration. See [INSTALL.txt](INSTALL.txt).

## Tuning

Optional `%LOCALAPPDATA%\ClickableScrollbars\ClickableScrollbars.ini`:

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
| `default_pixels_per_notch` / `calibration_samples` | 13 / 7 | starting wheel step and how many observations the median uses |
| `cooldown_ms` | 0 | shortest gap between two track-click jumps |
| `drag_threshold` | 10 | px of vertical movement that starts a drag |
| `drag_max_step_px` / `drag_max_notches` | 220 / 40 | per-frame guards against a pointer teleport |
| `use_window_capture` | 1 | try the game's own window device context before the desktop one |
| `log_interval_ms` / `trace_lines` / `trace_events` | 1000 / 48 / 0 | log rate limit, retained decisions, per-emission tracing |
| `error_limit` | 8 | frame errors tolerated before the addon stops |
| `dump_captures` | 0 | write that many capture BMPs next to the log (diagnosis only) |

## Status

Offline verification: 49 detector tests, 58 runtime tests, 13 platform tests
and the package check pass. The detector replay against the captured live
frames is exact rather than lenient: clicking the Armory thumb is a grab with
the pointer sprite over it, clicking the Career thumb is a grab, and clicking
above and below either bar is a track press whose pixel is the dark panel
(private evidence under `artifacts/ui-research/strips`). The animated harness
(`artifacts/ui-research/debug_runtime.lua`) measures the behaviour against a
game model whose list eases towards its target: a matched click lands 2 px from
the pointer with no nudge, a game with a 1.7× larger wheel step is corrected by
a single nudge to 4 px, an ignored wheel is reported instead of chased, and a
drag moves the target exactly with the pointer (the residual on screen is the
game's own easing, not an input queue).

**In-game validation is pending** — deploy, then click above and below a thumb
in Armory → Career and in an equipment grid, drag a thumb, and read the log:
`capture_source` and `capture_ms_avg` show which capture path is in use and what
it costs, `pages` / `drags` / `corrections` / `no_response` count what happened,
and the `trace` lines explain each decision.

## Build

```powershell
python -B ClickableScrollbars/scripts/build.py
```

The build validates the `-- HD2-Addon:` declaration, compiles the source with
the same LuaJIT the other mods use, runs both Lua suites and the package check,
rebuilds `data/9ba626afa44a3aa3.patch_0`, re-reads it with the repository's
patch inspector, then writes `releases/Clickable-Scrollbars-v2.2.zip`.

Run `python scripts/privacy_audit.py --zip releases/Clickable-Scrollbars-v2.2.zip` to
re-check the published source inventory and the packaged archive.

AI-assisted development with GPT-6 Astra.

Helldivers 2 and its assets belong to their respective owners. This is an
unofficial mod project.
