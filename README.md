> Release **v2.14.1** for Steam build 25480438 / EXE 1.8.46015.0. Offline checks passed; scrollbar dragging works in live play.

# Clickable Scrollbars — v2.14.1

Adds smooth click-and-drag scrolling to Helldivers 2 Armory equipment, mission loadout, Career, Display settings and Options bindings menus.
Requires [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader/releases/latest) v18 / API 1.

- Grab the thumb and move vertically anywhere horizontally. The original grab point stays fixed.
- Click the track to centre the thumb there, then keep holding to drag.
- Both ends clamp cleanly. Release, focus loss and menu changes cancel ownership.
- Ordinary clicks outside a supported scrollbar do not capture pixels, inject input or write diagnostic logs.
- Unsupported, hidden or invalid menus are left alone. The old screenshot/wheel fallback is no longer used by the runtime.

## Install

Close the game, replace the previous standalone package with `Clickable-Scrollbars-v2.14.1.zip` in Arsenal or HD2MM, enable it with Bingus Shared Loader v18, then Purge / Deploy. With Arsenal's default priority, put the loader last. Use one mod manager and one copy of this addon.

Vanilla Plus Megapack v32 already contains the same addon code; use either the Megapack or this package, not both.

## Settings

Optional file: `%LOCALAPPDATA%/ClickableScrollbars/ClickableScrollbars.ini`.

| Key | Default | Meaning |
| --- | ---: | --- |
| `enabled` | 1 | Set to 0 to disable the addon. |
| `native` | 1 | Set to 0 to disable native interaction; there is no wheel fallback. |
| `native_verify_ms` | 200 | Delay before verifying native movement. |
| `diagnostics` | 0 | Set to 1 to enable interaction traces and periodic log writes. |
| `log_interval_ms` | 5000 | Minimum interval between diagnostic log writes. |
| `error_limit` | 8 | Frame errors before the addon stops. |

Legacy pixel-detector settings no longer affect runtime interaction. An old `native=0` override must be removed or changed to `native=1` to enable scrolling.

## Validation

Supported game: Steam build 25480438 / EXE 1.8.46015.0. Offline checks cover the Armory, Career and Display settings scrollbars; scrollbar dragging works in live play. The mission loadout scrollbar and the Display settings fix have not been confirmed separately in game. Measured in recorded play the addon costs under 0.01 ms per frame. See [validation](docs/VALIDATION.md).

Diagnostic output, when enabled, goes to `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ClickableScrollbars.log`. Startup, shutdown and actual errors can still write a log. Private logs and machine details are excluded from releases.

Run `python -B scripts/build.py` to build. See [build instructions](CONTRIBUTING.md).

AI-assisted development with GPT-6 Astra and Claude Opus 5.5. This is an unofficial mod.

Release **v2.14.1** changes only the documentation; the addon is identical to v2.14, which supports Steam build 25480438. v2.13 fixed Display scrollbar drags activating options and tabs while left click is held.

Current version: **v2.14.1**, for game build **25480438**. See [changes](CHANGELOG.md) and [validation coverage](docs/MIGRATION_VALIDATION.md).
