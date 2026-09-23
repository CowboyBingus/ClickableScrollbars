# Scrollbar implementation

Equipment and Career use different native scroll owners. A hidden equipment
grid can remain allocated while Career is visible, so owner selection checks
resolved widget visibility before accepting a gesture.

On build 25327279 the Armory controller is dispatch kind 224. The mission
loadout screen uses kind 229, with its 48-item grid at controller+864032. The
captured screen stack maps state 5 to Armory and state 14 to loadout. Both use
the equipment grid's native scroll model; Career uses the Armory controller's
separate scroll container. Rendered widgets provide track bounds and thumb
size. Native entry-point checks and bounded reads reject unsupported layouts.

A press stores a fixed grab offset and captures the visible owner. During the
hold, vertical pointer movement determines a clamped normalized scroll value;
horizontal pointer movement does not affect the gesture. Each update validates
the owner and layout again. Release, focus loss, menu changes or a failed write
end ownership. Failed native holds do not switch to wheel input mid-gesture.

Equipment cancels the existing animation, calls the scrollbar setter, updates
the pixel offset and invokes the existing layout solver in that order. Career
uses its container position setter. Neither native route emits mouse-wheel or
button events, preventing held gestures from activating other menu controls.

The runtime now requires native owner visibility and track geometry before it
accepts a press. Missing or unsupported owners return without capture. Native
verification reads the rendered thumb instead of falling back to pixel capture.
Only update processes input; render is left untouched. Diagnostic traces and
periodic disk writes are opt-in. Legacy detector helpers are retained for
offline tests but are not entered by runtime gestures.

The source, tests and supported game fingerprints are public. Local probes,
screenshots, logs, extracted game data and machine details are excluded.
See [validation](VALIDATION.md) for offline coverage and in-game confirmation.

## Display settings input capture (v2.13)

The earlier settings guard wrote 0.499 to the list's field at +34124. That field
is a timer: update RVA 0x180a800 adds the frame delta while it is below 0.5, and
row handler 0x180b130 then accepts input at or above 0.5. An ordinary frame
therefore re-enabled rows. Category handler 0x19955a0 and the outer tab buttons
also read the UI selection independently of that timer.

The settings gesture now uses the game's input-consumption routine at
0x12fde90 with action 0xA00000000 and the same -1 duration used by its buttons.
The input owner comes from game.dll+0x347cf18. This routine clears the selection
edge and both value fields, including the per-player copies; clearing only a
press edge would leave held selection active. Its entry signature is checked
alongside the existing native setters before enabling native interaction.

Consumption starts only after a supported settings scrollbar hit. It continues
through mouse-up even if the scroll owner or layout changes, a write fails, or
focus is lost and regained. Scrolling still cancels under those conditions.
The input latch retains only the bridge needed to resolve the input singleton;
it does not dereference a stale settings controller. No timer restoration,
cursor constraint, synthetic mouse event or screenshot is needed.

These findings come from the local native-code capture for Steam build 25327279.
The runtime simulator executes the timer update and separate row/tab readers
after the addon callback, reproducing the old failure and verifying the fix.
