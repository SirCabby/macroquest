#!/usr/bin/env bash
# ============================================================================
# Provision MacroQuest's x86-windows dependencies on Linux with clang-cl.
# Builds each vcpkg port for the x86-windows-static triplet using the cross
# toolchain (see clang-cl-win32.toolchain.cmake). Safe to re-run; vcpkg skips
# already-built ports.
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VCPKG="$REPO_ROOT/contrib/vcpkg/vcpkg"
CROSS="$REPO_ROOT/cmake/cross"

if [[ ! -x "$VCPKG" ]]; then
    echo "vcpkg not bootstrapped. Run: $REPO_ROOT/contrib/vcpkg/bootstrap-vcpkg.sh -disableMetrics" >&2
    exit 1
fi

# Dependencies that currently cross-build cleanly. freetype uses [core] to avoid
# the brotli tool-copy step, which fails when cross-compiling.
# luajit/pe-parse use cross overlay ports from cmake/cross/vcpkg-ports.
PORTS=(
    fmt glm spdlog wil dxsdk-d3dx detours
    "freetype[core]" asio date argon2 protobuf sqlite3
    luajit sol2 yaml-cpp                       # lua plugin
    "curl-84[schannel]" cpr pe-parse           # loader
)

echo ">> Provisioning ${#PORTS[@]} ports for x86-windows-static via clang-cl ..."
"$VCPKG" install "${PORTS[@]/%/:x86-windows-static}" \
    --overlay-triplets="$CROSS/triplets" \
    --overlay-ports="$CROSS/vcpkg-ports" \
    --overlay-ports="$REPO_ROOT/contrib/vcpkg-ports" \
    --x-buildtrees-root="$REPO_ROOT/contrib/vcpkg/buildtrees" \
    --downloads-root="$REPO_ROOT/contrib/vcpkg/downloads"

echo ">> Done. Installed libs:"
ls "$REPO_ROOT/contrib/vcpkg/installed/x86-windows-static/lib/"*.lib 2>/dev/null || true
