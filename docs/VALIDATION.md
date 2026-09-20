# Validation

## Offline checks that pass

- Detector: 49 cases, including a coloured pointer sprite painted over a thumb,
  a bright interruption inside a bar, a coloured band that must split a bar, an
  adaptive brightness case, the 1080p/1440p/2160p geometry scaling with the ini
  overrides and clamps, and the two captured live strips replayed with exact
  expectations (grab inside the thumb, track press outside it).
- Runtime: 58 cases against a scripted platform, covering the whole burst on the
  click frame, a repeat click that changes nothing, one-to-one dragging with no
  capture during the drag, a pointer teleport that re-baselines instead of
  scrolling, a mismatched wheel step corrected by a bounded number of nudges,
  `no_response` for an ignored wheel, a doubled retry that finds a thumb outside
  the strip (and the same click failing when the retry is disabled), a display
  change that rescales the geometry and drops the learned step, error tolerance
  and the log contents.
- Windows platform: 13 cases that exercise the FFI bindings, the capture path,
  the display-height query and the sampler outside the game.
- Package: the manager ZIP is re-read entry by entry, its payload is compared
  with the build output and the payload is checked for forbidden APIs.

## Not yet run

- In-game confirmation of the released build. The loader discovers the addon
  (its declaration and log have been seen in game), the detector reads the real
  bars, and the log records every decision, but the shipped build of this
  version has not been played by a maintainer yet.
- Manager harness import for this ZIP: the isolated Arsenal and HD2MM fixtures
  used by the megapack family are not part of this repository.

The log at `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ClickableScrollbars.log`
is the acceptance instrument: `capture_source` and `capture_ms_avg` show which
capture path is in use and what it costs, `pages` / `drags` / `corrections` /
`no_response` count what happened, and the `trace` lines explain each decision.
