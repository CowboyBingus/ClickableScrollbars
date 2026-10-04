# Third-party dependencies

The build uses [LuaJIT](https://github.com/LuaJIT/LuaJIT) to compile and test the
addon source, and the repository's own patch inspector
(`tools/bin/hd2-patch-inspect.exe`, built on the vendored
[filediver](https://github.com/xypwn/filediver) Stingray package reader,
BSD-3-Clause). No third-party code is shipped in the release ZIP.

At runtime the addon calls Windows functions available to the game process
through LuaJIT FFI: `GetCursorPos`, `GetAsyncKeyState`, `GetForegroundWindow`,
`GetWindowThreadProcessId`, `GetClientRect`, `ClientToScreen`, `IsWindow` and
`GetSystemMetrics` (user32), and `GetTickCount64`, `GetCurrentProcessId`,
`GetCurrentProcess`, `GetModuleHandleA` and `ReadProcessMemory` (kernel32), the
last to read the game's menu state in its own process. To scroll it calls the
game's own scroll, layout and input routines and writes bounded scroll values
into the game's menu objects. It does not synthesize input, patch executable
code, load a library of its own, or replace a game file.

Helldivers 2 and its game assets belong to their respective owners. This is an
unofficial mod project. A supported game installation is required for building;
no game executable, extracted resource, native decompilation or crash dump is
included in source control. The one memory capture is
`tests/fixtures/ui_armory_25327279.lua`: the Armory menu fields read in Steam
build 25327279, replayed offline by `tests/test_current_ui.lua`.

This repository is licensed under the Zero-Clause BSD license (0BSD, see `LICENSE`): use, copy, modify and distribute it for any purpose, with no conditions. Upstream dependencies keep their own licenses.
