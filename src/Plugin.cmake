# Generated from Plugin.props
# This file should be included in CMakeLists.txt files that need these settings
# NOTE: Import order preserved from original .props file

include_guard()

set(PATH_TO_Plugin_DIR ${CMAKE_CURRENT_LIST_DIR})

macro(target_Plugin_props TARGET_NAME)

    # ---------------------------------------------------------------------
    # Import from original props file
    # ---------------------------------------------------------------------
    # Depends on conversion of: ./Common.props
    include(${PATH_TO_Plugin_DIR}/Common.cmake)
    target_Common_props(${TARGET_NAME})
    
    # TODO: Manual conversion required for element: ItemGroup
    
    # TODO: Manual conversion required for element: CopyMQPluginFiles
    
    # ---------------------------------------------------------------------
    # Import from original props file
    # ---------------------------------------------------------------------
    # Depends on conversion of: ./private/Plugin-private.props
    if(EXISTS "${PATH_TO_Common_DIR}/./private/Plugin-private.cmake")
        include(${PATH_TO_Plugin_DIR}/./private/Plugin-private.cmake)
        target_Plugin_private_props(${TARGET_NAME})
    endif()

    # set the output directory, MQBinaryDirName is a generator expression which prevents
    # cmake from auto-appending the configuration
    set_target_properties(${TARGET_NAME} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/${MQBinaryDirName}/plugins" # .exe files
            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/${MQBinaryDirName}/plugins" # .dll files
            ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/${MQBinaryDirName}/plugins" # .lib files
    )

    # Cross build: UTF-16 .rc sources are transcoded for llvm-rc (see
    # mq_cross_utf8_rc in Common.cmake), and the plugin's NASM sources
    # (WindowOverride trampolines) are assembled here because the VS NASM
    # integration (add_nasm_sources) is a no-op under Ninja.
    if(MQ_CROSS_LINUX)
        mq_cross_utf8_rc(${TARGET_NAME})

        get_target_property(_mq_plugin_sources ${TARGET_NAME} SOURCES)
        foreach(_mq_src IN LISTS _mq_plugin_sources)
            if(_mq_src MATCHES "\\.asm$" AND NOT _mq_src MATCHES "64\\.asm$" AND NOT _mq_src MATCHES "AssemblyMacros")
                find_program(MQ_NASM nasm REQUIRED)
                get_filename_component(_mq_asm_abs "${_mq_src}" ABSOLUTE)
                get_filename_component(_mq_asm_name "${_mq_asm_abs}" NAME_WE)
                set(_mq_asm_obj "${CMAKE_CURRENT_BINARY_DIR}/${_mq_asm_name}.win32.obj")
                add_custom_command(OUTPUT "${_mq_asm_obj}"
                    COMMAND "${MQ_NASM}" -f win32 -DARCH_X86 -I "${CMAKE_SOURCE_DIR}/src/eqlib/include/"
                            "${_mq_asm_abs}" -o "${_mq_asm_obj}"
                    DEPENDS "${_mq_asm_abs}" "${CMAKE_SOURCE_DIR}/src/eqlib/include/eqlib/AssemblyMacros.asm"
                    COMMENT "Assembling ${_mq_asm_name}.asm (nasm, win32)"
                    VERBATIM)
                set_source_files_properties("${_mq_asm_obj}" PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
                target_sources(${TARGET_NAME} PRIVATE "${_mq_asm_obj}")
            endif()
        endforeach()
    endif()


    # ---------------------------------------------------------------------
    # Linker settings
    # ---------------------------------------------------------------------
    # Library directories
#    target_link_directories(${TARGET_NAME} PRIVATE
#        "${CMAKE_BINARY_DIR}/bin/$<CONFIG>"
#    )

    add_dependencies(${TARGET_NAME} pluginapi MQ2Main)
    # Additional dependencies
    target_link_libraries(${TARGET_NAME} PRIVATE
#        "$<$<CONFIG:Debug>:fmtd.lib>"
#        "$<$<CONFIG:Release>:fmt.lib>"
#        "mq2main.lib"
        pluginapi
        MQ2Main
    )
    
     
endmacro()
