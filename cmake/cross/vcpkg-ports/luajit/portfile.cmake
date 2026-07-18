# ============================================================================
# LuaJIT for the MacroQuest Linux -> Windows (x86) cross build.
#
# The stock (and MacroQuest) luajit ports drive src/msvcbuild.bat with nmake,
# which only works on Windows. This port reproduces what msvcbuild.bat does
# for a *static x86* build, in a cross-friendly way:
#
#   1. Build the host tools (minilua, buildvm) with the native compiler.
#      buildvm is parameterized for the *target* (x86 / Windows) via
#      -DLUAJIT_TARGET / -DLUAJIT_OS, exactly like LuaJIT's own Makefile
#      cross-build support.
#   2. Run dynasm + buildvm to generate buildvm_arch.h, the lj_*def.h headers,
#      and lj_vm.obj (buildvm's peobj writer emits a Win32 COFF object
#      directly - no assembler needed).
#   3. Compile lj_*.c / lib_*.c with clang-cl via the usual vcpkg toolchain
#      and archive them together with lj_vm.obj into lua51.lib
#      (see CMakeLists.txt next to this file).
#
# Same source REF as contrib/vcpkg-ports/luajit; the msvcbuild.bat patches are
# irrelevant here because msvcbuild.bat is not used.
# ============================================================================

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO LuaJIT/LuaJIT
    REF e826d0c101d750fac8334d71e221c50d8dbe236c
    SHA512 d53334e00603fbfef558111e12d5cda50271e22b2ba3dc29e7084ee5b5d38f83a2378d2d6b3da4311d7591209f15a5b56bea9025f62568cb0904c6ef3ee40176
    HEAD_REF v2.1
)

set(gen "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-gen")
file(REMOVE_RECURSE "${gen}")
file(MAKE_DIRECTORY "${gen}")

find_program(MQ_HOST_CC NAMES cc gcc clang REQUIRED)

# --- 1. minilua (host) ------------------------------------------------------
# LuaJIT's code generators must run with the TARGET pointer size, so the host
# tools are built 32-bit (-m32) for the Win32 target.
vcpkg_execute_required_process(
    COMMAND "${MQ_HOST_CC}" -m32 -O2 -o "${gen}/minilua" "${SOURCE_PATH}/src/host/minilua.c" -lm
    WORKING_DIRECTORY "${SOURCE_PATH}/src"
    LOGNAME "host-minilua-${TARGET_TRIPLET}"
)

# msvcbuild.bat runs this first: generates src/luajit.h from luajit_rolling.h.
# In a tarball (no .git) the release version comes from the .relver file.
file(READ "${SOURCE_PATH}/.relver" _lj_relver)
file(WRITE "${SOURCE_PATH}/src/luajit_relver.txt" "${_lj_relver}")
vcpkg_execute_required_process(
    COMMAND "${gen}/minilua" host/genversion.lua
    WORKING_DIRECTORY "${SOURCE_PATH}/src"
    LOGNAME "host-genversion-${TARGET_TRIPLET}"
)

# --- 2. dynasm: buildvm_arch.h (x86 / Windows: -D WIN -D JIT -D FFI) --------
vcpkg_execute_required_process(
    COMMAND "${gen}/minilua" "${SOURCE_PATH}/dynasm/dynasm.lua" -LN
            -D WIN -D JIT -D FFI
            -o "${gen}/buildvm_arch.h" vm_x86.dasc
    WORKING_DIRECTORY "${SOURCE_PATH}/src"
    LOGNAME "host-dynasm-${TARGET_TRIPLET}"
)

# --- 3. buildvm (host binary, target-parameterized) -------------------------
file(GLOB buildvm_sources "${SOURCE_PATH}/src/host/buildvm*.c")
vcpkg_execute_required_process(
    COMMAND "${MQ_HOST_CC}" -m32 -O2
            -I "${SOURCE_PATH}/src" -I "${SOURCE_PATH}/dynasm" -I "${gen}"
            -DLUAJIT_TARGET=LUAJIT_ARCH_x86 -DLUAJIT_OS=LUAJIT_OS_WINDOWS
            -o "${gen}/buildvm" ${buildvm_sources}
    WORKING_DIRECTORY "${SOURCE_PATH}/src"
    LOGNAME "host-buildvm-${TARGET_TRIPLET}"
)

# --- 4. generated VM object + headers (mirrors msvcbuild.bat) ---------------
set(ALL_LIB
    lib_base.c lib_math.c lib_bit.c lib_string.c lib_table.c
    lib_io.c lib_os.c lib_package.c lib_debug.c lib_jit.c lib_ffi.c
    lib_buffer.c)

foreach(mode_out IN ITEMS
        "peobj;lj_vm.obj"
        "bcdef;lj_bcdef.h"
        "ffdef;lj_ffdef.h"
        "libdef;lj_libdef.h"
        "recdef;lj_recdef.h"
        "vmdef;vmdef.lua")
    list(GET mode_out 0 mode)
    list(GET mode_out 1 out)
    vcpkg_execute_required_process(
        COMMAND "${gen}/buildvm" -m "${mode}" -o "${gen}/${out}" ${ALL_LIB}
        WORKING_DIRECTORY "${SOURCE_PATH}/src"
        LOGNAME "host-buildvm-${mode}-${TARGET_TRIPLET}"
    )
endforeach()

vcpkg_execute_required_process(
    COMMAND "${gen}/buildvm" -m folddef -o "${gen}/lj_folddef.h" lj_opt_fold.c
    WORKING_DIRECTORY "${SOURCE_PATH}/src"
    LOGNAME "host-buildvm-folddef-${TARGET_TRIPLET}"
)

# --- 5. target build (clang-cl via the vcpkg toolchain) ---------------------
vcpkg_cmake_configure(
    SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}"
    OPTIONS
        "-DLUAJIT_SOURCE_DIR=${SOURCE_PATH}"
        "-DLUAJIT_GEN_DIR=${gen}"
)
vcpkg_cmake_install()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share")

# Install the CMake config the MacroQuest build consumes (find_package(luajit))
include(CMakePackageConfigHelpers)
configure_package_config_file(
        "${CMAKE_CURRENT_LIST_DIR}/luajit-config.cmake.in"
        "${CURRENT_PACKAGES_DIR}/share/${PORT}/luajit-config.cmake"
        INSTALL_DESTINATION "share/${PORT}"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYRIGHT")
