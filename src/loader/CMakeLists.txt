# Generated from MacroQuest.vcxproj
# This file is designed to work with add_subdirectory()

# ---------------------------------------------------------------------
# Props file includes
# ---------------------------------------------------------------------
include("../Common.cmake")

# ---------------------------------------------------------------------
# vcpkg dependencies
# ---------------------------------------------------------------------
find_package(crashpad REQUIRED)
find_package(spdlog REQUIRED)
find_package(wil REQUIRED)
find_package(date REQUIRED)
find_package(curl-84 REQUIRED)
find_package(cpr REQUIRED)
find_package(pe-parse REQUIRED)
find_package(protobuf REQUIRED)

# ---------------------------------------------------------------------
# Header files
# ---------------------------------------------------------------------
set(MacroQuest_HEADERS
    "../../include/mq/base/BuildInfo.h"
    "../../include/mq/utils/Markov.h"
    "../../include/mq/utils/Naming.h"
    "LoaderAutoLogin.h"
    "Crashpad.h"
    "ImGui.h"
    "imgui_backend/imgui_engine.h"
    "imgui_backend/imgui_impl_dx11.h"
    "imgui_backend/imgui_impl_win32.h"
    "MacroQuest.h"
    "PostOffice.h"
    "ProcessMonitor.h"
    "resource.h"
    "WinToastLib.h"
)

source_groups("Header Files" ${MacroQuest_HEADERS})

# ---------------------------------------------------------------------
# Other files
# ---------------------------------------------------------------------
set(MacroQuest_OTHERFILES
    "MacroQuest.rc"
)

source_group("Resource Files" FILES ${MacroQuest_OTHERFILES})

# ---------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------
set(MacroQuest_SOURCES
    "../common/HotKeys.cpp"
    "LoaderAutoLogin.cpp"
    "LoaderAutoLoginImGui.cpp"
    "Crashpad.cpp"
    "ImGui.cpp"
    "imgui_backend/imgui_engine.cpp"
    "imgui_backend/imgui_impl_dx11.cpp"
    "imgui_backend/imgui_impl_win32.cpp"
    "MacroQuest.cpp"
    "PostOffice.cpp"
    "PostOfficeImGui.cpp"
    "ProcessList.cpp"
    "ProcessMonitor.cpp"
    "RemoteOps.cpp"
    "Utility.cpp"
    "WinToastLib.cpp"
)

source_groups("Source Files" ${MacroQuest_SOURCES})

# ---------------------------------------------------------------------
# Target definition
# ---------------------------------------------------------------------
add_executable(MacroQuest
    ${MacroQuest_HEADERS}
    ${MacroQuest_OTHERFILES}
    ${MacroQuest_SOURCES}
)

set_target_properties(MacroQuest PROPERTIES FOLDER "core/applications")

# ---------------------------------------------------------------------
# Apply props file configurations
# ---------------------------------------------------------------------
target_Common_props(MacroQuest)

# ---------------------------------------------------------------------
# Link vcpkg dependencies
# ---------------------------------------------------------------------
target_link_libraries(MacroQuest PRIVATE
    crashpad::crashpad
    spdlog::spdlog
    WIL::WIL
    date::date
    CURL-84::libcurl
    cpr::cpr
    pe-parse::pe-parse
    protobuf::libprotobuf
)

# ---------------------------------------------------------------------
# Project dependencies
# ---------------------------------------------------------------------
add_dependencies(MacroQuest imgui login routing)

target_link_libraries(MacroQuest PRIVATE imgui login routing)

# ---------------------------------------------------------------------
# Include directories
# ---------------------------------------------------------------------
target_include_directories(MacroQuest PRIVATE
    "${VCPKG_IncludeStatic}/crashpad"
    "${CMAKE_SOURCE_DIR}/include"
)

# ---------------------------------------------------------------------
# Compiler options
# ---------------------------------------------------------------------
target_compile_options(MacroQuest PRIVATE
    "$<$<CONFIG:Release>:/O2>"
    "/std:c++17"
    "$<$<CONFIG:Release>:/Oi>"
    "$<$<CONFIG:Release>:/Gy>"
)

# ---------------------------------------------------------------------
# Link libraries
# ---------------------------------------------------------------------
# The vcxproj supplies these via $(LoaderDependenciesDebug/Release); the vcpkg
# libraries from those lists arrive through imported targets here, so only the
# Windows SDK libraries remain.
set(LoaderDependenciesDebug "d3d11.lib;setupapi.lib;imm32.lib;ws2_32.lib;wldap32.lib;version.lib")
set(LoaderDependenciesRelease "${LoaderDependenciesDebug}")

target_link_libraries(MacroQuest PRIVATE
    "$<$<CONFIG:Debug>:${LoaderDependenciesDebug}>"
    "$<$<CONFIG:Release>:${LoaderDependenciesRelease}>"
)

# ---------------------------------------------------------------------
# Linker options
# ---------------------------------------------------------------------
target_link_options(MacroQuest PRIVATE
    "$<$<CONFIG:Release>:/OPT:ICF>"
    "$<$<CONFIG:Release>:/OPT:REF>"
)

# ---------------------------------------------------------------------
# Character set defines
# ---------------------------------------------------------------------
target_compile_definitions(MacroQuest PRIVATE
    "_MBCS"
)

# ---------------------------------------------------------------------
# Wine tray helper (Linux cross build only)
# ---------------------------------------------------------------------
# Native StatusNotifierItem helper so the wine-hosted loader gets a working
# panel icon on SNI desktops (see src/loader/wine/mq_tray_helper.c). Built
# with the host compiler against sd-bus and staged next to MacroQuest.exe.
if(MQ_CROSS_LINUX)
    find_program(MQ_HOST_CC_TRAY NAMES cc gcc clang)
    find_program(MQ_PYTHON3 NAMES python3)
    if(MQ_HOST_CC_TRAY AND MQ_PYTHON3)
        if(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set(_mq_tray_outdir "${CMAKE_BINARY_DIR}/bin/debug")
        else()
            set(_mq_tray_outdir "${CMAKE_BINARY_DIR}/bin/release")
        endif()
        set(_mq_tray_icon_h "${CMAKE_CURRENT_BINARY_DIR}/mq_tray_icon.h")
        add_custom_command(OUTPUT "${_mq_tray_icon_h}"
            COMMAND "${MQ_PYTHON3}" "${CMAKE_SOURCE_DIR}/cmake/cross/gen_tray_icon.py"
                    "${CMAKE_CURRENT_SOURCE_DIR}/icon1.ico" "${_mq_tray_icon_h}" 48
            DEPENDS "${CMAKE_SOURCE_DIR}/cmake/cross/gen_tray_icon.py"
                    "${CMAKE_CURRENT_SOURCE_DIR}/icon1.ico"
            COMMENT "Generating tray icon pixmap for mq-tray-helper"
            VERBATIM)
        set(_mq_tray_helper "${_mq_tray_outdir}/mq-tray-helper")
        add_custom_command(OUTPUT "${_mq_tray_helper}"
            COMMAND "${MQ_HOST_CC_TRAY}" -O2 -Wall
                    -o "${_mq_tray_helper}"
                    "${CMAKE_CURRENT_SOURCE_DIR}/wine/mq_tray_helper.c"
                    -I "${CMAKE_CURRENT_BINARY_DIR}" -lsystemd
            DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/wine/mq_tray_helper.c" "${_mq_tray_icon_h}"
            COMMENT "Building mq-tray-helper (native SNI tray for wine)"
            VERBATIM)
        add_custom_target(mq-tray-helper ALL DEPENDS "${_mq_tray_helper}")
    else()
        message(STATUS "mq-tray-helper skipped (host cc or python3 not found)")
    endif()
endif()

# ============================================================================
# MANUAL CONVERSION NOTES
# ============================================================================
#
# - Review and adjust as needed
