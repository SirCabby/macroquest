# ============================================================================
# Linux -> Windows (x86 / Win32) cross toolchain for MacroQuest
# ============================================================================
# Uses LLVM clang-cl + lld-link against a Microsoft CRT/Windows SDK tree that
# was fetched with `xwin` (https://github.com/jake-shadle/xwin) and splatted in
# the "/winsysroot" layout.
#
# This lets MacroQuest's Win32 (emu) configuration be built on Linux without
# Visual Studio. It is intentionally self-contained and does NOT affect the
# normal MSVC / Visual Studio build path.
#
# Required:
#   MQ_WINSYSROOT  - path to the xwin splat root (contains "VC" and
#                    "Windows Kits"). May be passed with -D or via the
#                    MQ_WINSYSROOT environment variable.
# ============================================================================

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86)

# ----------------------------------------------------------------------------
# Locate the Windows sysroot (xwin splat)
# ----------------------------------------------------------------------------
if(NOT MQ_WINSYSROOT AND DEFINED ENV{MQ_WINSYSROOT})
    set(MQ_WINSYSROOT "$ENV{MQ_WINSYSROOT}")
endif()
if(NOT MQ_WINSYSROOT)
    set(MQ_WINSYSROOT "$ENV{HOME}/.local/share/winsysroot")
endif()
if(NOT EXISTS "${MQ_WINSYSROOT}/VC/Tools/MSVC")
    message(FATAL_ERROR
        "MQ_WINSYSROOT does not look like an xwin splat: ${MQ_WINSYSROOT}\n"
        "Expected to find VC/Tools/MSVC underneath it.")
endif()
# Cache so sub-builds (try_compile, vcpkg) inherit it.
set(MQ_WINSYSROOT "${MQ_WINSYSROOT}" CACHE PATH "xwin Windows sysroot" FORCE)

# Discover the concrete MSVC + SDK version directories.
file(GLOB _mq_msvc_dirs "${MQ_WINSYSROOT}/VC/Tools/MSVC/*")
list(GET _mq_msvc_dirs 0 MQ_MSVC_DIR)
file(GLOB _mq_sdk_dirs "${MQ_WINSYSROOT}/Windows Kits/10/Lib/*")
list(GET _mq_sdk_dirs 0 MQ_SDK_LIB_DIR)
file(GLOB _mq_sdk_inc_dirs "${MQ_WINSYSROOT}/Windows Kits/10/Include/*")
list(GET _mq_sdk_inc_dirs 0 MQ_SDK_INC_DIR)

# ----------------------------------------------------------------------------
# Compilers / tools
# ----------------------------------------------------------------------------
find_program(MQ_CLANG_CL NAMES clang-cl REQUIRED)
find_program(MQ_LLD_LINK NAMES lld-link REQUIRED)
find_program(MQ_LLVM_LIB NAMES llvm-lib REQUIRED)
find_program(MQ_LLVM_RC  NAMES llvm-rc  REQUIRED)
find_program(MQ_LLVM_MT  NAMES llvm-mt  REQUIRED)

set(CMAKE_C_COMPILER   "${MQ_CLANG_CL}")
set(CMAKE_CXX_COMPILER "${MQ_CLANG_CL}")
set(CMAKE_C_COMPILER_TARGET   i686-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET i686-pc-windows-msvc)
set(CMAKE_LINKER "${MQ_LLD_LINK}")
set(CMAKE_AR     "${MQ_LLVM_LIB}")
set(CMAKE_MT     "${MQ_LLVM_MT}")
set(CMAKE_RC_COMPILER "${MQ_LLVM_RC}")

# The xwin splat only carries the RELEASE, statically-linked CRT (matching
# MacroQuest's /MT build). Steer CMake's own compiler-detection try-compiles at
# that same runtime so they don't reach for msvcrtd.lib / libcmtd.lib.
set(CMAKE_TRY_COMPILE_CONFIGURATION "Release")
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# CMAKE_MSVC_RUNTIME_LIBRARY only works under policy CMP0091 NEW. Ports with an
# old cmake_minimum_required (freetype, sqlite3, glm, date) run with CMP0091 OLD,
# where CMake's platform default of /MD in the per-config flags wins — mixing
# dynamic-CRT objects into an otherwise /MT link. Do what vcpkg's own
# scripts/toolchains/windows.cmake (which this file replaces as the chainload)
# does: cache-set the per-config flags with the static CRT flag baked in.
set(CMAKE_C_FLAGS_RELEASE   "/MT /O2 /Oi /Gy /DNDEBUG /Z7" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELEASE "/MT /O2 /Oi /Gy /DNDEBUG /Z7" CACHE STRING "")
set(CMAKE_C_FLAGS_DEBUG     "/MTd /Ob0 /Od /Z7" CACHE STRING "")
set(CMAKE_CXX_FLAGS_DEBUG   "/MTd /Ob0 /Od /Z7" CACHE STRING "")

# clang-cl needs to know the target + sysroot on every invocation.
# /winsysroot supplies both the header search paths and (when linking through
# the driver) the library paths.
# -fdelayed-template-parsing matches MSVC's late template-body parsing, which a
# lot of MacroQuest/eqlib template code relies on (e.g. `this` used in a
# discarded `if constexpr` branch of a function template).
# -Wno-invalid-token-paste: MacroQuest's expression-stack macros (MQ2Utilities.cpp)
#   rely on MSVC's lenient handling of `##` that forms invalid tokens (it keeps the
#   operands juxtaposed); clang errors by default. This flag restores MSVC behaviour.
set(_mq_cl_flags "--target=i686-pc-windows-msvc -fms-compatibility -fms-extensions -fdelayed-template-parsing -Wno-invalid-token-paste /winsysroot \"${MQ_WINSYSROOT}\"")
# C only: feature-detection sources (curl's CurlTests.c etc.) rely on lax C
# that cl.exe accepts with a warning but newer clang rejects (e.g. int* passed
# as u_long* to ioctlsocket). Downgrade those back to warnings so configure
# checks give the same answers as under MSVC.
set(_mq_c_lax "-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=implicit-int")
set(CMAKE_C_FLAGS_INIT   "${_mq_cl_flags} ${_mq_c_lax}")
set(CMAKE_CXX_FLAGS_INIT "${_mq_cl_flags}")

# We invoke lld-link directly (MSVC-style rules), so it does not see the
# /winsysroot the driver would have expanded. Feed it the library paths.
set(_mq_libpaths
    "/libpath:\"${MQ_MSVC_DIR}/lib/x86\""
    "/libpath:\"${MQ_SDK_LIB_DIR}/ucrt/x86\""
    "/libpath:\"${MQ_SDK_LIB_DIR}/um/x86\"")
string(JOIN " " _mq_libpaths_str ${_mq_libpaths})
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_mq_libpaths_str}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_mq_libpaths_str}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_mq_libpaths_str}")

# llvm-rc needs the SDK/CRT include dirs to resolve <winres.h> etc.
set(CMAKE_RC_FLAGS_INIT "-I \"${MQ_SDK_INC_DIR}/um\" -I \"${MQ_SDK_INC_DIR}/shared\" -I \"${MQ_MSVC_DIR}/include\"")

# ----------------------------------------------------------------------------
# Search behaviour + test-run under wine
# ----------------------------------------------------------------------------
set(CMAKE_FIND_ROOT_PATH "${MQ_WINSYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

find_program(MQ_WINE NAMES wine)
if(MQ_WINE)
    set(CMAKE_CROSSCOMPILING_EMULATOR "${MQ_WINE}")
endif()
