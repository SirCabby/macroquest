# ============================================================================
# Stage MacroQuest data files into the build output directory (Linux cross
# build). Replicates what the Visual Studio build does through
# tools/build_scripts/MQ2Main_PostBuild.ps1 and the CopyMQPluginFiles target
# in src/Plugin.props, neither of which can run without powershell/MSBuild.
#
# Usage:
#   cmake -DMQ_ROOT=<repo root> -DMQ_STAGE_DIR=<build>/bin/release -P stage_data.cmake
#
# Copy semantics match the VS build: config files are never overwritten
# (user-editable), everything else is refreshed when the source changes.
# ============================================================================

if(NOT MQ_ROOT OR NOT MQ_STAGE_DIR)
    message(FATAL_ERROR "MQ_ROOT and MQ_STAGE_DIR must be defined")
endif()

# Copy one file, preserving VS-build semantics.
function(mq_stage_file src dst never_overwrite)
    if(never_overwrite AND EXISTS "${dst}")
        return()
    endif()
    get_filename_component(_dst_dir "${dst}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dst_dir}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${src}" "${dst}")
endfunction()

# --- 1. data/BinCopy.txt (MQ2Main_PostBuild.ps1) ----------------------------
# Each line is a glob relative to data/; matches are copied to the stage dir
# under the same relative path. Config files are never overwritten.
set(_data "${MQ_ROOT}/data")
file(STRINGS "${_data}/BinCopy.txt" _bincopy_lines)
foreach(_pattern IN LISTS _bincopy_lines)
    string(STRIP "${_pattern}" _pattern)
    if(_pattern STREQUAL "")
        continue()
    endif()
    file(GLOB _matches RELATIVE "${_data}" "${_data}/${_pattern}")
    foreach(_rel IN LISTS _matches)
        if(IS_DIRECTORY "${_data}/${_rel}")
            continue()
        endif()
        if(_rel MATCHES "^config/")
            mq_stage_file("${_data}/${_rel}" "${MQ_STAGE_DIR}/${_rel}" TRUE)
        else()
            mq_stage_file("${_data}/${_rel}" "${MQ_STAGE_DIR}/${_rel}" FALSE)
        endif()
    endforeach()
endforeach()

# --- 2. License, luarocks (MQ2Main_PostBuild.ps1) ---------------------------
mq_stage_file("${MQ_ROOT}/LICENSE.md" "${MQ_STAGE_DIR}/resources/LICENSE.md" FALSE)
# Win32 build ships the 32-bit luarocks as luarocks.exe
mq_stage_file("${_data}/luarocks32.exe" "${MQ_STAGE_DIR}/luarocks.exe" FALSE)

# --- 3. Optional binaries (silent no-ops in VS release builds too) ----------
# crashpad_handler.exe: crashpad is stubbed in the cross build (no handler).
# D3DX9d_43.dll: the *debug* D3DX9 redist; dxsdk-d3dx only ships it in its
# debug layout, so VS release deployments never include it either. Both are
# staged if present, mirroring MQ2Main_PostBuild.ps1's Copy-LatestFile
# (which silently skips missing sources).
set(_crashpad "${MQ_ROOT}/contrib/vcpkg/installed/x86-windows-static/tools/crashpad_handler.exe")
if(EXISTS "${_crashpad}")
    mq_stage_file("${_crashpad}" "${MQ_STAGE_DIR}/crashpad_handler.exe" FALSE)
else()
    message(STATUS "stage: crashpad_handler.exe not available (crashpad is stubbed) - skipped")
endif()
foreach(_d3dx9d
        "${MQ_ROOT}/contrib/vcpkg/installed/x86-windows/bin/D3DX9d_43.dll"
        "${MQ_ROOT}/contrib/vcpkg/installed/x86-windows/debug/bin/D3DX9d_43.dll")
    if(EXISTS "${_d3dx9d}")
        mq_stage_file("${_d3dx9d}" "${MQ_STAGE_DIR}/D3DX9d_43.dll" FALSE)
        break()
    endif()
endforeach()

# --- 4. Plugin data dirs (CopyMQPluginFiles in src/Plugin.props) ------------
# Each plugin may carry resources/, lua/, macros/, config/ trees that merge
# into the same-named directories next to the binaries.
file(GLOB _plugin_dirs "${MQ_ROOT}/src/plugins/*")
foreach(_plugin IN LISTS _plugin_dirs)
    if(NOT IS_DIRECTORY "${_plugin}")
        continue()
    endif()
    foreach(_kind resources lua macros config)
        set(_src_root "${_plugin}/${_kind}")
        if(NOT IS_DIRECTORY "${_src_root}")
            continue()
        endif()
        file(GLOB_RECURSE _files RELATIVE "${_src_root}" "${_src_root}/*")
        foreach(_rel IN LISTS _files)
            if(_kind STREQUAL "config")
                mq_stage_file("${_src_root}/${_rel}" "${MQ_STAGE_DIR}/${_kind}/${_rel}" TRUE)
            else()
                mq_stage_file("${_src_root}/${_rel}" "${MQ_STAGE_DIR}/${_kind}/${_rel}" FALSE)
            endif()
        endforeach()
    endforeach()
endforeach()

message(STATUS "stage: data files staged into ${MQ_STAGE_DIR}")
