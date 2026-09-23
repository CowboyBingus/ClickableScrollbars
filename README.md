The UI repair supports the captured Armory and mission loadout controllers for build 25327279. The loadout controller is kind 229 and embeds its 48-item grid at offset 864032. In-game loadout interaction still needs confirmation.

> Current compatibility candidate: Clickable Scrollbars v2.13, Steam build 25327279 / EXE 1.8.45850.0. Use Bingus Shared Loader v16. The Display scrollbar input fix passes offline checks; installed interaction still needs confirmation.

# Clickable Scrollbars — v2.13

Adds smooth click-and-drag scrolling to Helldivers 2 Armory equipment, mission loadout, Career, Display settings and Options bindings menus.
Requires Bingus Shared Loader v16 or newer / API 1.

- Grab the thumb and move vertically anywhere horizontally. The original grab point stays fixed.
- Click the track to centre the thumb there, then keep holding to drag.
- Both ends clamp cleanly. Release, focus loss and menu changes cancel ownership.
- Ordinary clicks outside a supported scrollbar do not capture pixels, inject input or write diagnostic logs.
- Unsupported, hidden or invalid menus are left alone. The old screenshot/wheel fallback is no longer used by the runtime.

## Install

Close the game, replace the previous standalone package with `Clickable-Scrollbars-v2.13.zip` in Arsenal or HD2MM, enable it with Bingus Shared Loader v16+, then Purge / Deploy. With Arsenal's default priority, put the loader last. Use one mod manager and one copy of this addon.

Vanilla Plus Megapack v26 still pins v2.10; use this standalone update for the loadout fix.

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

Supported game: Steam build 25327279 / EXE 1.8.45850.0. Existing offline checks cover Armory and Career. The new loadout path needs offline regression and in-game confirmation. See [validation](docs/VALIDATION.md).

Diagnostic output, when enabled, goes to `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ClickableScrollbars.log`. Startup, shutdown and actual errors can still write a log. Private logs and machine details are excluded from releases.

Run `python -B scripts/build.py` to build. See [build instructions](CONTRIBUTING.md).

AI-assisted development with GPT-6 Astra. This is an unofficial mod.

Release **v2.13** fixes Display scrollbar drags activating options and tabs while left click is held. Offline regression checks pass; in-game confirmation remains pending.
