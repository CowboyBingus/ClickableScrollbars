# Third-party dependencies

The build uses [LuaJIT](https://github.com/LuaJIT/LuaJIT) to compile and test the
addon source, and the repository's own patch inspector
(`tools/bin/hd2-patch-inspect.exe`, built on the vendored
[filediver](https://github.com/xypwn/filediver) Stingray package reader,
BSD-3-Clause). No third-party code is shipped in the release ZIP.

At runtime the addon uses only Windows APIs available to the game process
(`GetAsyncKeyState`, `GetCursorPos`, `BitBlt`, `SendInput`) through LuaJIT FFI.
It does not write to game memory, patch executable code, load a library, or
replace a game file.

Helldivers 2 and its game assets belong to their respective owners. This is an
unofficial mod project. A supported game installation is required for building;
no game executable, extracted resource, native decompilation, memory capture or
crash dump is included in source control.

No repository-wide license has been selected.
