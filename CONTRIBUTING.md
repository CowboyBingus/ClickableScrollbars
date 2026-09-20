# Build

Use Windows x64, Python 3.10+ and the LuaJIT commit pinned in `dependencies.json`. Build LuaJIT with `msvcbuild.bat nogc64` from an x64 Native Tools command prompt, then place the executable at `tools/src/LuaJIT/src/luajit.exe` or set `HD2_LUAJIT`.

Run `python scripts/build.py`. The build checks the `-- HD2-Addon:` declaration, compiles the source, runs the detector, runtime and Windows-platform suites plus the package check, rebuilds `build/9ba626afa44a3aa3.patch_0`, re-reads it with the patch inspector at `tools/bin/hd2-patch-inspect.exe`, and writes `releases/Clickable-Scrollbars-v2.1.zip`.

The build refuses a source file that mentions hook, DLL-loading or memory-mutation APIs, so the addon stays a loader-delivered Lua resource. It never installs the mod, writes into the game directory or launches the game. A supported game installation is needed for the inspector; the addon itself is verified against the pinned game fingerprints in `scripts/build.py`.

`tests/test_detector.lua` and `tests/test_install.lua` replay captured live bar strips and drive the runtime against a scripted platform. Synthetic fixtures only: no game memory, process capture, log or dump is committed.

# Publication

Only `publication-files.json` entries are public. Run `python scripts/privacy_audit.py --zip releases/Clickable-Scrollbars-v2.1.zip --git` after staging a release to check the source inventory, archive metadata and Git history.

Do not commit local paths, process captures, dumps, logs, extracted game resources, credentials or a personal Git identity. Commit as CowboyBingus with the GitHub noreply address, publish release assets only from the audited build, and never copy files into a game directory by hand.
