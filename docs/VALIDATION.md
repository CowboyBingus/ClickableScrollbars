# v2.6 validation

## Verified offline

The build runs the detector, scripted runtime, synthetic native-memory tests,
Windows API binding/buffer-order checks, performance tests, profiler/fuzzer,
interaction simulator, Lua compilation and archive/package inspection.

The interaction simulator now supplies no automatic game drag. Native list
movement happens only through the addon's native-apply call. The separate wheel
fallback models the reported behavior where a wheel event during a held click
activates the widget under the pointer.

Regression coverage includes:

- Three-column grids with nine-item cache groups; stable controller identity
  across fresh FFI pointer wrappers.
- A fixed grab point before and after verification, small sub-row movements,
  no writes while the pointer is stationary, both clamps and return from them.
- Off-centre thumb clicks with no movement, track-click-to-drag continuation,
  sideways wandering, tab crossing and release over other controls.
- Controller changes, focus loss, ignored native writes, persistent retirement
  of a failing controller and the native=0 override.
- No wheel fallback during a failed native hold; no deferred drag notches after
  release; deferred clicks require a prior mouse-up frame and the original target.
- Three UI scales, 60 randomized drags, detection fuzzing and bounded capture cost.
- Separate equipment/Career ownership, hidden widgets, native track transforms
  and window origins, Career padding and the equipment setter/cancellation order.
- Native drags at horizontal positions far to either side of the track, both
  vertical ends, reversal, release and menu changes; no wheel events or captures.

See `build/offline-tests.txt` and `build/build-report.json` for the current
results. Build artifacts and live evidence are private local outputs.

The profiler's isolated scan comparison clears earlier LuaJIT traces before
warming both variants. Earlier benchmark cases could otherwise leave one
variant interpreted; enabling JIT tracing alone changed the result. The
original performance thresholds are retained, and detector code is unchanged.

## Read-only live evidence

The running supported game DLL matched the repository fingerprint. The live
Armory grid had 3 actual columns at `grid+47540`, while `grid+602088` contained
9. Reading the latter as a column count explains `grid columns out of range`
in the existing log.

The v2.5 log showed native retirement followed by restricted wheel fallback.
The running Career screen retained a hidden equipment grid. Career instead
uses the controller's container at +318472, with separate track and thumb
widgets. Its frame routine derives the thumb from the container position.
The revised reader resolved that visible Career owner and matched the screen's
track and thumb geometry. The equipment handler cancels an animation, updates
the generic scrollbar through its setter, then solves the list layout.
All four called native entry points were checked against the running game.
No revised native setter was invoked in the game during this inspection.

Windows platform checks, including desktop capture, passed on the interactive
desktop (16 checks). The release build records desktop capture as verified.

## In-game confirmation

The user confirmed that v2.6 works correctly after deployment. That confirmation
applies to the exact runtime source SHA-256 recorded in `scripts/build.py`; a
changed source does not inherit the verified flag. No hardware details, local
paths, session captures or private logs are included in the release.

## Remaining limitation

Menus outside supported equipment and Career use guarded, quantized wheel input
and pause outside the measured scrollbar.

## In-game regression checklist

Install the release through the mod manager and restart the game. If an older
INI disabled the native route, remove `native=0` or change it to `native=1`.

1. In both an equipment grid and Career, grab the top, centre and bottom of the thumb. A click
   without motion must not jump. Move slowly by a few pixels, then drag quickly.
2. Stop for at least half a second, then move another pixel: no extra jump.
3. Drag past both ends, sideways over tabs and list items, then return. The
   original list must follow the fixed grab point; no tab or item may activate.
4. Release over a tab. A subsequent ordinary click must still select that tab.
5. Change categories, close/reopen Armory and alt-tab during a hold. A new grab
   must work and the abandoned gesture must emit nothing.
6. Move far left and right while held at the same height: the scroll position
   must remain unchanged. Move vertically there: the original list must follow.
7. Inspect the v2.6 log for native_writes/native_ok, zero errors, and unexpected
   native retirement. Thumb movement alone is insufficient: verify list content
   and visible items move with it.
