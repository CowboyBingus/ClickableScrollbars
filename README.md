The UI repair updates controller registration for build 25327279. A live read-only Armory capture resolves the 55-item grid and scrollbar geometry. Offline interaction tests pass; clicking and dragging the installed repair still need in-game confirmation.


# Clickable Scrollbars — v2.10

Adds smooth click-and-drag scrolling to Helldivers 2 equipment and Career menus.
Requires Bingus Shared Loader v16 or newer / API 1.

- Grab the thumb and move vertically anywhere horizontally. The original grab point stays fixed.
- Click the track to centre the thumb there, then keep holding to drag.
- Both ends clamp cleanly. Release, focus loss and menu changes cancel ownership.
- Ordinary clicks outside a supported scrollbar do not capture pixels, inject input or write diagnostic logs.
- Unsupported, hidden or invalid menus are left alone. The old screenshot/wheel fallback is no longer used by the runtime.

## Install

Close the game, replace the previous standalone package with `Clickable-Scrollbars-v2.10.zip` in Arsenal or HD2MM, enable it with Bingus Shared Loader v16+, then Purge / Deploy. With Arsenal's default priority, put the loader last. Use one mod manager and one copy of this addon.

Vanilla Plus Megapack v26 and its Rows variant include this version.

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

Supported game: Steam build 25327279 / EXE 1.8.45850.0. Offline tests cover native interaction, hidden owners, gameplay clicks, callback preservation, bounded work and archive integrity. v2.6 received user confirmation in-game; the changed v2.10 source still needs in-game confirmation. See [validation](docs/VALIDATION.md).

Diagnostic output, when enabled, goes to `%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/ClickableScrollbars.log`. Startup, shutdown and actual errors can still write a log. Private logs and machine details are excluded from releases.

Run `python -B scripts/build.py` to build. See [build instructions](CONTRIBUTING.md).

AI-assisted development with GPT-6 Astra. This is an unofficial mod.

See [validation coverage](docs/MIGRATION_VALIDATION.md) for the scope of the release checks.

Current version: **v2.10**, for game build **25327279**. See [changes](CHANGELOG.md) and [validation coverage](docs/MIGRATION_VALIDATION.md).
