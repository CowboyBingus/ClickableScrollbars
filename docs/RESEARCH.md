# Scrollbar implementation

Equipment and Career use different native scroll owners. A hidden equipment
grid can remain allocated while Career is visible, so owner selection checks
resolved widget visibility before accepting a gesture.

The Armory controller is located through dispatch kind 222. Equipment uses its
item grid; Career uses its separate scroll container. The rendered widgets
provide track bounds and thumb size. Native entry-point checks and bounded
reads reject unsupported game layouts before a native write.

A press stores a fixed grab offset and captures the visible owner. During the
hold, vertical pointer movement determines a clamped normalized scroll value;
horizontal pointer movement does not affect the gesture. Each update validates
the owner and layout again. Release, focus loss, menu changes or a failed write
end ownership. Failed native holds do not switch to wheel input mid-gesture.

Equipment cancels the existing animation, calls the scrollbar setter, updates
the pixel offset and invokes the existing layout solver in that order. Career
uses its container position setter. Neither native route emits mouse-wheel or
button events, preventing held gestures from activating other menu controls.

The fallback detector remains available for other menu bars. It uses guarded,
quantized wheel input and only emits while the pointer remains on its original
target. It does not provide the native routes' unrestricted horizontal drag.

The source, tests and supported game fingerprints are public. Local probes,
screenshots, logs, extracted game data and machine details are excluded.
See [validation](VALIDATION.md) for offline coverage and in-game confirmation.
