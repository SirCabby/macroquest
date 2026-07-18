# Linux cross-build for MacroQuest (Win32 / emu) — EXPERIMENTAL

MacroQuest is a Windows/MSVC project: it produces a DLL that injects into the
Windows EverQuest client, and its build hard-locks to the Visual Studio
generator. This directory adds an **opt-in** path to cross-compile the
**Win32 (emu)** configuration **on Linux** using the LLVM `clang-cl` /
`lld-link` toolchain against a Microsoft SDK/CRT obtained with
[`xwin`](https://github.com/jake-shadle/xwin).

It is fully gated behind `-DMQ_CROSS_LINUX=ON` and does **not** affect the normal
Visual Studio build.

## Why clang-cl (and not mingw)

eqlib's Win32 path (`include/eqlib/Offsets.h`, `WindowOverride.h`) implements the
EQ client's virtual-function trampolines with `__declspec(naked)` + MSVC
Intel-syntax inline `__asm`. GCC/mingw cannot parse MS inline asm at all;
`clang-cl` compiles it, links with `lld-link`, and the result runs under wine.
That was verified end-to-end before any MacroQuest code was built.

## One-time setup (all user-space, no sudo)

1. **LLVM** — `clang-cl`, `lld-link`, `llvm-lib`, `llvm-rc`, `llvm-mt` (LLVM 18+).
2. **CMake 3.31.x** — *not* 4.x. CMake 4 removed `cmake_minimum_required(<3.5)`
   compatibility, which several older vcpkg ports (freetype, protobuf 3.21)
   still declare.
3. **Ninja** and **NASM** (NASM only needed later, for the eqlib `AssemblyFunctions.asm`
   trampolines when producing a shared library).
4. **Windows SDK + CRT** via xwin:
   ```
   xwin --accept-license --arch x86,x86_64 splat \
        --use-winsysroot-style --output ~/.local/share/winsysroot
   ```
   Point `MQ_WINSYSROOT` at that directory (the toolchain defaults to
   `~/.local/share/winsysroot`).
5. **Bootstrap vcpkg**:
   ```
   contrib/vcpkg/bootstrap-vcpkg.sh -disableMetrics
   ```

## Build

```bash
# 1. Provision the x86-windows-static dependencies (clang-cl):
cmake/cross/provision-deps.sh

# 2. Configure (default subdir set is the six core components):
cmake/cross/configure.sh "" build_cross            # static libs
cmake/cross/configure.sh "" build_cross -DMQ_STATIC_BUILD=OFF   # real DLLs

# 3. Build:
cmake --build build_cross -j
```

Extra arguments after the build dir are passed through to cmake verbatim.

## Pieces in this directory

| File | Purpose |
|------|---------|
| `clang-cl-win32.toolchain.cmake` | CMake toolchain: clang-cl → `i686-pc-windows-msvc`, `/winsysroot`, lld-link libpaths, `-fdelayed-template-parsing`, Release/static-CRT try-compiles. |
| `triplets/x86-windows-static.cmake` | vcpkg overlay triplet that chainloads the toolchain (`VCPKG_CMAKE_SYSTEM_NAME=Windows`). |
| `vcpkg-ports/detours/` | CMake-based detours port (upstream uses NMake, which vcpkg can't run off-Windows). |
| `provision-deps.sh` | Builds the dependency set for `x86-windows-static`. |
| `configure.sh` | Configures the cross build via classic (non-manifest) vcpkg. |

## Status

**Toolchain & dependencies: working.** These vcpkg ports cross-build cleanly for
`x86-windows-static`: `fmt`, `glm`, `spdlog`, `wil`, `dxsdk-d3dx`, `detours`,
`freetype[core]`, `asio`, `date`, `argon2`, `protobuf`, `sqlite3`.

**Six components build and link (zero errors, reproducible from scratch, ~44s):**

| Target | Artifact |
|--------|----------|
| `src/eqlib`   | `eqlib-static.lib` (22 TUs, ~9 MB, real functional trampolines) |
| `src/imgui`   | `imgui-static.lib` |
| `contrib/zep` | `zep.lib` |
| `src/routing` | `routing.lib` (includes protobuf codegen) |
| `src/login`   | `login.lib` |
| `src/main`    | `MQ2Main-static.lib` (55 TUs, ~66 MB — the MacroQuest core) |

`MQ2Main` is the big one: crashpad is stubbed (`cmake/cross/stubs/crashpad`, no-op),
its powershell build events and `.rc`/unity `datatypes/*.cpp` are handled for the
cross build, and ~15 clang-strictness source fixes were applied (see below).

The hard parts are solved. eqlib — the MacroQuest-specific core, with thousands of
naked member-function trampolines and MSVC inline asm — fully cross-compiles with
functional (non-stubbed) trampolines. See the two `[[...]]`-worthy fixes:

- **Detour macro** (`MemoryPatcher.h`): clang rejects taking an unqualified
  member-function address, so `DETOUR_TRAMPOLINE_DEF` was split into a free form
  plus `DETOUR_TRAMPOLINE_DEF_MEMBER(cls, ...)` (class scope) under `#if
  defined(__clang__)`; MSVC keeps the original macro unchanged. Member call
  sites are converted mechanically (see `scratchpad convert_detours.py`).
- **Naked trampolines** (`Offsets.h`, `WindowOverride.h`): clang only accepts
  `__declspec(naked)` on free functions, so `EQLIB_NAKED` (`Config.h`) maps to
  `__attribute__((naked))` under clang (which *does* allow naked members). clang
  also forbids non-asm statements in naked bodies, so the `using VFT = …` alias
  is hoisted to namespace scope with a unique name in the clang variants. All
  gated by `EQLIB_CROSS_COMPILE` so the existing `__clang__` tooling stubs are
  untouched.
- Misc: `.contains()`→`.count()` (C++17); build stays at C++17 (eqstd's vendored
  MSVC-STL headers and fmt/spdlog consteval break under clang C++20).

**Clang-strictness source fixes applied for main** (all valid on MSVC too): the
`DEPRECATE` macro is a no-op under clang (it was placed after array declarators
where clang binds `[[deprecated]]` to the type); `blech/Blech.h` → `Blech/Blech.h`
(case-sensitive FS); `std::erase` → erase-remove (C++20→17); several `typename`
insertions for dependent types (`DSL::Term/Reducer/Modifier`); `MaskEntry`
aggregate `emplace_back(a,b)` → `push_back({a,b})`; `ItemPtr` through varargs →
`.get()`; and `-Wno-invalid-token-paste` in the toolchain for the expression-stack
macros. Three detour sites in `MQ2AutoInventory.cpp` were mis-attributed by the
converter for nested `class Outer::Inner` (now fixed in `convert_detours.py`).

**The multi-DLL link works (`MQ_STATIC_BUILD=OFF`).** The real MacroQuest module
set — `eqlib.dll` (`/BASE:0x03400000`, ~2000 exports incl. the NASM trampolines),
`imgui.dll`, `MQ2Main.dll` (`/BASE:0x03000000`) — links with lld-link, **all 14
plugins** build as DLLs importing from them (autobank, autologin, bzsrch, chat,
chatwnd, custombinds, eqbugfix, hud, itemdisplay, labels, lua, map, targetinfo,
xtarinfo), and the **loader (`MacroQuest.exe`) links and starts under wine**.
eqlib/MQ2Main carry proper VERSIONINFO resources (UTF-8 transcode). All DLLs
load cleanly under wine (`LoadLibrary` smoke test); a full from-scratch
configure+build of everything is ~2 minutes.

What the DLL phase needed (all committed):

- **Static CRT for old vcpkg ports** (`clang-cl-win32.toolchain.cmake`): the
  chainload toolchain replaces vcpkg's `windows.cmake`, so ports with an old
  `cmake_minimum_required` (CMP0091 OLD: freetype, sqlite3, glm, date) silently
  built with `/MD` and dragged `msvcrt.lib` into `/MT` links. The toolchain now
  cache-sets the per-config compiler flags with `/MT`(`d`) baked in, exactly like
  vcpkg's own Windows toolchain. (Re-provision those four ports if upgrading an
  old tree.)
- **`imanim` sources** were missing from the generated `src/imgui/CMakeLists.txt`
  (stale vs. `imgui.vcxproj`; on Windows the vcxproj conversion regenerates it).
- **`/DEFAULTLIB` resolution** (`src/Common.cmake`): the `#pragma comment(lib,
  "eqlib")`-style references resolve via libpath, so the cross build adds
  `lib/<config>/` to the link directories.
- **Plugin `.rc`/`.asm` handling** (`src/Plugin.cmake`, under `MQ_CROSS_LINUX`):
  UTF-16 resource scripts are transcoded to UTF-8 for llvm-rc via iconv;
  plugin NASM sources (the per-plugin `WindowOverride` trampolines in
  `AssemblyFunctions.asm`) are assembled with `nasm -f win32 -DARCH_X86` and the
  objects linked in (the VS NASM integration is a no-op under Ninja).
- Source fixes (MSVC-safe): `#pragma comment(lib, "Crypt32.lib")` /
  `"Psapi.lib"` → lowercase, `<Windowsx.h>`/`<Wbemidl.h>`/`<Tlhelp32.h>`/
  `<Commctrl.h>` → SDK's on-disk casing (xwin keeps canonical case; lld-link
  and a case-sensitive FS don't forgive mismatches); autologin's
  `GetInitialLoginProfile` moved below the tinyfsm state class definitions
  (`Login::is_in_state<S>` needs a complete `S`; MSVC's end-of-TU instantiation
  hid this); lua plugin `std::ranges::find_if` → iterator-pair `std::find_if`
  (cross build is C++17) and one `std::string` through varargs → `.c_str()`;
  `src/loader/PostOffice.h` made self-contained (`<windows.h>`).

The **lua plugin** dependencies cross-build via ports: `sol2`, `yaml-cpp`
(stock), and a **cross luajit overlay port** (`cmake/cross/vcpkg-ports/luajit`)
that builds LuaJIT's host tools natively (`-m32`, matching the Win32 pointer
size), runs dynasm + `buildvm -m peobj` to emit the VM as a Win32 COFF object,
and compiles `lj_*.c`/`lib_*.c` with clang-cl into `lua51.lib` — no
msvcbuild.bat/nmake involved.

The **loader** dependencies: `curl-84` (MQ port; two portable fixes: a
case-matching `curl-84-config.cmake` alias and an `if(EXISTS)` guard for the
release-only debug rename), `cpr`, and `pe-parse` (cross overlay port that
drops MSVC's `/analyze` flag under clang). curl's configure checks needed
C-only `-Wno-error=incompatible-pointer-types` etc. in the toolchain (modern
clang hard-errors on K&R-isms cl.exe accepts, breaking feature detection).
crashpad stays a no-op stub (`cmake/cross/stubs/crashpad`), extended to cover
the loader's report-database UI surface; crash reporting is disabled.

**Deployable layout**: the VS build stages data files through powershell
post-build events; the cross build replicates that with an always-run
`mq_stage_data` target (`cmake/cross/stage_data.cmake`). It processes
`data/BinCopy.txt` (default config — never overwritten once present —,
macros, resources), `LICENSE.md`, `luarocks32.exe` → `luarocks.exe`, and each
plugin's `resources|lua|macros|config` trees (the lua plugin's `lua/` script
library). The result in `bin/<config>/` is a MacroQuest folder at full parity
with a VS *release* deployment except `crashpad_handler.exe` (crashpad is
stubbed). `D3DX9d_43.dll` is the debug D3DX9 redist and is absent from VS
release deployments too (the ps1 skips missing sources silently); both are
staged automatically if they exist.

## Remaining

1. **Run against a real client**: nothing has been tested inside EQ yet — wine
   `LoadLibrary`/launch smoke tests only.
2. **Crash reporting** is compiled out (crashpad is a no-op stub, so there is
   also no `crashpad_handler.exe` to ship). Building real crashpad
   (GN/mini_chromium) under clang-cl cross remains unattempted.

## Resuming in a new session

Everything needed is committed to the working tree; the toolchain lives in
`~/.local` and `~/.local/share/winsysroot` (already installed). To continue:

```bash
export PATH="$HOME/.local/bin:$PATH"      # cmake 3.31, ninja, xwin, nasm
# deps already provisioned under contrib/vcpkg/installed/x86-windows-static
# (fresh machine: cmake/cross/provision-deps.sh)
SUBDIRS="src/eqlib;src/imgui;contrib/zep;src/routing;src/login;src/main;src/loader"
for p in pluginapi autobank autologin bzsrch chat chatwnd custombinds eqbugfix hud itemdisplay labels lua map targetinfo xtarinfo; do
    SUBDIRS="$SUBDIRS;src/plugins/$p"
done
cmake/cross/configure.sh "$SUBDIRS" build_all -DMQ_STATIC_BUILD=OFF
cmake --build build_all -j
```

Result: `build_all/bin/release/` is a deployable MacroQuest folder:
`eqlib.dll`, `imgui.dll`, `MQ2Main.dll`, `MacroQuest.exe`, `plugins/*.dll`
(14 plugins), plus the staged `lua/`, `macros/`, `resources/`, `config/`
trees and `luarocks.exe`.
