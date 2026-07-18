#!/usr/bin/env bash
# ============================================================================
# Configure a MacroQuest Linux cross build (Win32/emu) with clang-cl + lld-link.
#
# Usage:
#   cmake/cross/configure.sh [SUBDIRS] [BUILD_DIR] [EXTRA_CMAKE_ARGS...]
#     SUBDIRS   - semicolon list of subdirs to build (default: src/eqlib)
#                 e.g. "src/eqlib;src/imgui;contrib/zep"
#     BUILD_DIR - output dir (default: build_cross)
#     EXTRA_CMAKE_ARGS - passed through to cmake, e.g. -DMQ_STATIC_BUILD=OFF
#
# After configuring:  cmake --build <BUILD_DIR> -j
#
# Requirements (all installable in user space, no sudo — see README.md):
#   - clang-cl / lld-link / llvm-{lib,rc,mt}  (LLVM)
#   - cmake >= 3.30 (use 3.31.x, NOT 4.x: old vcpkg ports need <3.5 policy compat)
#   - ninja
#   - an xwin Windows SDK/CRT splat at $MQ_WINSYSROOT (default ~/.local/share/winsysroot)
#   - dependencies provisioned via provision-deps.sh
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CROSS="$REPO_ROOT/cmake/cross"
SUBDIRS="${1:-src/eqlib;src/imgui;contrib/zep;src/routing;src/login;src/main}"
BUILD_DIR="${2:-$REPO_ROOT/build_cross}"
shift $(( $# > 2 ? 2 : $# ))

: "${MQ_WINSYSROOT:=$HOME/.local/share/winsysroot}"
export MQ_WINSYSROOT

cmake -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/contrib/vcpkg/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="$CROSS/clang-cl-win32.toolchain.cmake" \
    -DVCPKG_TARGET_TRIPLET=x86-windows-static \
    -DVCPKG_OVERLAY_TRIPLETS="$CROSS/triplets" \
    -DVCPKG_MANIFEST_MODE=OFF \
    -DVCPKG_APPLOCAL_DEPS=OFF \
    -DMQ_CROSS_LINUX=ON \
    -DMQ_STATIC_BUILD=ON \
    -DMQ_BUILD_PLUGINS=OFF \
    -DMQ_CROSS_SUBDIRS="$SUBDIRS" \
    -DCMAKE_BUILD_TYPE=Release \
    "$@"

echo
echo ">> Configured. Build with:  cmake --build $BUILD_DIR -j"
