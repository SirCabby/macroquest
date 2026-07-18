# Generated from Common.props
# This file should be included in CMakeLists.txt files that need these settings
# NOTE: Import order preserved from original .props file

include_guard()

set(PATH_TO_Common_DIR ${CMAKE_CURRENT_LIST_DIR})

# The Linux cross build compiles resources with llvm-rc, which cannot read
# UTF-16 .rc files. This transcodes any UTF-16 .rc source of the target to a
# UTF-8 copy in the build tree and compiles that instead. No-op outside the
# cross build.
function(mq_cross_utf8_rc TARGET_NAME)
    if(NOT MQ_CROSS_LINUX)
        return()
    endif()
    get_target_property(_mq_rc_sources ${TARGET_NAME} SOURCES)
    foreach(_mq_src IN LISTS _mq_rc_sources)
        if(NOT _mq_src MATCHES "\\.rc$")
            continue()
        endif()
        get_filename_component(_mq_rc_abs "${_mq_src}" ABSOLUTE)
        file(READ "${_mq_rc_abs}" _mq_rc_bom HEX LIMIT 2)
        if(NOT _mq_rc_bom STREQUAL "fffe")
            continue()
        endif()
        get_filename_component(_mq_rc_name "${_mq_rc_abs}" NAME_WE)
        set(_mq_rc_utf8 "${CMAKE_CURRENT_BINARY_DIR}/${_mq_rc_name}.utf8.rc")
        add_custom_command(OUTPUT "${_mq_rc_utf8}"
            COMMAND sh -c "iconv -f UTF-16LE -t UTF-8 '${_mq_rc_abs}' | sed '1s/^\\xEF\\xBB\\xBF//' > '${_mq_rc_utf8}'"
            DEPENDS "${_mq_rc_abs}"
            COMMENT "Transcoding ${_mq_rc_name}.rc to UTF-8 for llvm-rc"
            VERBATIM)
        set_source_files_properties("${_mq_rc_abs}" PROPERTIES HEADER_FILE_ONLY ON)
        set_source_files_properties("${_mq_rc_utf8}" PROPERTIES GENERATED TRUE)
        target_sources(${TARGET_NAME} PRIVATE "${_mq_rc_utf8}")
        # resource.h & friends live next to the original .rc; the transcoded
        # copy compiles from the build tree, so resolve them via include path.
        get_filename_component(_mq_rc_dir "${_mq_rc_abs}" DIRECTORY)
        target_include_directories(${TARGET_NAME} PRIVATE "${_mq_rc_dir}")
    endforeach()
endfunction()

macro(target_Common_props TARGET_NAME)

    # TODO: Manual conversion required for element: VcpkgMQInstallManifestDependencies
    
    # ---------------------------------------------------------------------
    # Import from original props file
    # ---------------------------------------------------------------------
    # Depends on conversion of: ./private/Common-private.props
    if(EXISTS "${PATH_TO_Common_DIR}/./private/Common-private.cmake")
        include(${PATH_TO_Common_DIR}/./private/Common-private.cmake)
        target_Common_private_props(${TARGET_NAME})
    endif()
    
    # ---------------------------------------------------------------------
    # Import from original props file
    # ---------------------------------------------------------------------
    # Depends on conversion of: ./eqlib/eqlib.props
    if(EXISTS "${PATH_TO_Common_DIR}/./eqlib/eqlib.cmake")
        include(${PATH_TO_Common_DIR}/./eqlib/eqlib.cmake)
        target_eqlib_props(${TARGET_NAME})
    endif()
    
    # ---------------------------------------------------------------------
    # PropertyGroup settings
    # ---------------------------------------------------------------------
    set(MQConfig "$<IF:$<CONFIG:Debug>,Debug,Release>")
    
    set(MQBinaryDirName "$<IF:$<CONFIG:Debug>,debug,release>")
    
    if(MQ_STATIC_BUILD)
        set(MQStaticBuild "true")
    else()
        set(MQStaticBuild "false")
    endif()
    
    if("${MQ_BUILD_SEPARATE}" STREQUAL "1")
        set(MQBuildDirectory "${CMAKE_SOURCE_DIR}/build/${eqlibClientTarget}/")
    elseif(NOT "${MQ_BUILD_SEPARATE}" STREQUAL "1")
        set(MQBuildDirectory "${CMAKE_SOURCE_DIR}/build/")
    endif()
    
    set(MQLibDir "${CMAKE_BINARY_DIR}/lib/${CMAKE_GENERATOR_PLATFORM}/$<CONFIG>/")
    
    set(MQ2BuildDirectory "${CMAKE_BINARY_DIR}/")
    
    set(MQ2LibDir "${MQLibDir}")
    
#    set(MQ2MainLibs "$<IF:$<CONFIG:Debug>,fmtd.lib;psapi.lib;version.lib;pathcch.lib;kernel32.lib;user32.lib;gdi32.lib;winspool.lib;comdlg32.lib;advapi32.lib;shell32.lib;ole32.lib;oleaut32.lib;uuid.lib;odbc32.lib;odbccp32.lib;base.lib;common.lib;client.lib;util.lib;sqlite3.lib,fmt.lib;psapi.lib;version.lib;pathcch.lib;kernel32.lib;user32.lib;gdi32.lib;winspool.lib;comdlg32.lib;advapi32.lib;shell32.lib;ole32.lib;oleaut32.lib;uuid.lib;odbc32.lib;odbccp32.lib;base.lib;common.lib;client.lib;util.lib;sqlite3.lib>")
    set(MQ2MainLibs "$<IF:$<CONFIG:Debug>,psapi.lib;version.lib;pathcch.lib;kernel32.lib;user32.lib;gdi32.lib;winspool.lib;comdlg32.lib;advapi32.lib;shell32.lib;ole32.lib;oleaut32.lib;uuid.lib;odbc32.lib;odbccp32.lib,psapi.lib;version.lib;pathcch.lib;kernel32.lib;user32.lib;gdi32.lib;winspool.lib;comdlg32.lib;advapi32.lib;shell32.lib;ole32.lib;oleaut32.lib;uuid.lib;odbc32.lib;odbccp32.lib>")

#    set(ImGuiLibs "$<IF:$<CONFIG:Debug>,freetyped.lib,freetype.lib>")
    
    set(MQAmalgamLibs "MQ2Main-static.lib;${MQ2MainLibs};${ImGuiLibs}")
    
    set(MQAmalgamDefines "MQLIB_STATIC;EQLIB_STATIC;IMGUI_STATIC")
    
#    if(CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
#        set(VCPKG_IncludeStatic "${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows-static/include")
#    elseif(CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
#        set(VCPKG_IncludeStatic "${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows-static/include")
#    endif()
#
#    if(CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
#        set(VCPKG_IncludeDynamic "${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows/include")
#    elseif(CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
#        set(VCPKG_IncludeDynamic "${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows/include")
#    endif()
#
#    if(CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
#        set(VCPKG_LibraryDirs "$<IF:$<CONFIG:Debug>,${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows-static/debug/lib;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows-static/debug/lib/manual-link;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows/debug/lib,${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows-static/lib;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows-static/lib/manual-link;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x64-windows/lib>")
#    elseif(CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
#        set(VCPKG_LibraryDirs "$<IF:$<CONFIG:Debug>,${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows-static/debug/lib;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows-static/debug/lib/manual-link;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows/debug/lib,${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows-static/lib;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows-static/lib/manual-link;${CMAKE_SOURCE_DIR}/contrib/vcpkg/installed/x86-windows/lib>")
#    endif()
    
    if(CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
        set(PlatformLibraryDirectories "${CMAKE_SOURCE_DIR}/contrib/detours/lib")
    endif()
    
    target_link_options(${TARGET_NAME} PRIVATE "$<IF:$<CONFIG:Debug>,/INCREMENTAL,/INCREMENTAL:NO>")
    
#    set(ProtocolBufferDependsOn "VcpkgMQInstallManifestDependencies;${ProtocolBufferDependsOn}")

    # set the output directory, MQBinaryDirName is a generator expression which prevents
    # cmake from auto-appending the configuration (will be overridden in Plugin.cmake)
    set_target_properties(${TARGET_NAME} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/${MQBinaryDirName}" # .exe files
            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/${MQBinaryDirName}" # .dll files
            ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/${MQBinaryDirName}" # .lib files
    )
    
    # ---------------------------------------------------------------------
    # Compiler settings
    # ---------------------------------------------------------------------
    # Preprocessor definitions
    target_compile_definitions(${TARGET_NAME} PRIVATE
        "SOL_SAFE_USERTYPE"
        "_WINNT_WIN32=0x0601"
        "_WIN32_WINNT=0x0601"
        "SOL_SAFE_FUNCTIONS"
        "WIN32_LEAN_AND_MEAN"
        "_SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING"
        "NOMINMAX"
        "WINVER=0x0601"
        "$<$<BOOL:${MQ_STATIC_BUILD}>:MQLIB_STATIC>"
        "$<$<BOOL:${MQ_STATIC_BUILD}>:IMGUI_STATIC>"
        "GLM_FORCE_CTOR_INIT"
        "$<$<BOOL:${MQ_STATIC_BUILD}>:EQLIB_STATIC>"
        "$<$<CONFIG:Debug>:_DEBUG>"
        "SPDLOG_COMPILED_LIB"
    )
    
    # Include directories
    target_include_directories(${TARGET_NAME} PRIVATE
        "${CMAKE_SOURCE_DIR}/contrib/imgui"
        "${CMAKE_SOURCE_DIR}/include"
        "${CMAKE_SOURCE_DIR}/contrib/zep/include"
        "${CMAKE_SOURCE_DIR}/contrib/tinyfsm/include"
#        "${VCPKG_IncludeDynamic}"
        "${CMAKE_SOURCE_DIR}/contrib"
        "${CMAKE_SOURCE_DIR}/contrib/dxsdk90/include"
        "${CMAKE_SOURCE_DIR}/plugins"
#        "${VCPKG_IncludeStatic}"
        "${CMAKE_SOURCE_DIR}/src"
        "${CMAKE_SOURCE_DIR}/contrib/imgui/misc/cpp"
    )
    
    # Compiler options
    target_compile_options(${TARGET_NAME} PRIVATE
        "$<$<CONFIG:Debug>:/MTd>"
        "$<$<CONFIG:Debug>:/Ob0>"
        "/Gy"
        "$<$<CONFIG:Release>:/GF>"
        "/W3"
        "$<$<CONFIG:Release>:/MT>"
        "/utf-8"
        "/Zi"
        "/GS-"
        "$<$<CONFIG:Debug>:/Od>"
        "/MP"
        # NOTE: the cross build stays on C++17. MacroQuest's vendored eqstd headers
        # rely on MSVC's lenient constexpr rules that clang only accepts from C++23
        # on, and fmt/spdlog enable consteval format checks under C++20 that clang
        # also rejects — both are avoided at C++17.
        "/std:c++17"
    )
    
    # ---------------------------------------------------------------------
    # Linker settings
    # ---------------------------------------------------------------------
    # Library directories - needed for the pragma lib includes used in source
    # The cross build links with lld-link, which resolves the /DEFAULTLIB
    # references from those pragmas (eqlib.lib, MQ2Main.lib, ...) by searching
    # the libpath — point it at the per-config import-library directory.
    if(MQ_CROSS_LINUX)
        target_link_directories(${TARGET_NAME} PRIVATE
            "${CMAKE_BINARY_DIR}/lib/${MQBinaryDirName}")
    endif()
    target_link_directories(${TARGET_NAME} PRIVATE
        "${CMAKE_BINARY_DIR}/bin"
        "${CMAKE_BINARY_DIR}/lib"
#        "${PlatformLibraryDirectories}"
#        "${VCPKG_LibraryDirs}"
#        "${MQLibDir}"
#        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/"
    )
    
    # Additional dependencies
    target_link_libraries(${TARGET_NAME} PRIVATE
        "winmm.lib"
        "detours::detours"
        "fmt::fmt"
        "spdlog::spdlog"
    )

    # Linker options
    target_link_options(${TARGET_NAME} PRIVATE
        "/OPT:NOREF"
        "/OPT:NOICF"
        "/SUBSYSTEM:WINDOWS"
        "/DEBUG"
        "/SAFESEH:NO"
        "/DYNAMICBASE"
        "/NXCOMPAT"
    )
    
     
endmacro()
