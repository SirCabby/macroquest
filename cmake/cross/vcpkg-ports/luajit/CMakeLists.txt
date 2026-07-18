# Target-side build for the LuaJIT cross port: compiles the interpreter/JIT C
# sources with clang-cl and archives them with the buildvm-generated lj_vm.obj
# into lua51.lib (matching msvcbuild.bat's static mode: lj_*.c lib_*.c).
cmake_minimum_required(VERSION 3.20)
project(luajit C)

if(NOT LUAJIT_SOURCE_DIR OR NOT LUAJIT_GEN_DIR)
    message(FATAL_ERROR "LUAJIT_SOURCE_DIR and LUAJIT_GEN_DIR must be provided")
endif()

file(GLOB LUAJIT_CORE_SOURCES "${LUAJIT_SOURCE_DIR}/src/lj_*.c")
file(GLOB LUAJIT_LIB_SOURCES  "${LUAJIT_SOURCE_DIR}/src/lib_*.c")

add_library(lua51 STATIC
    ${LUAJIT_CORE_SOURCES}
    ${LUAJIT_LIB_SOURCES}
    "${LUAJIT_GEN_DIR}/lj_vm.obj"
)

target_include_directories(lua51 PRIVATE "${LUAJIT_GEN_DIR}" "${LUAJIT_SOURCE_DIR}/src")
target_compile_definitions(lua51 PRIVATE "_CRT_SECURE_NO_DEPRECATE")

install(TARGETS lua51 ARCHIVE DESTINATION lib)
install(FILES
    "${LUAJIT_SOURCE_DIR}/src/lua.h"
    "${LUAJIT_SOURCE_DIR}/src/luaconf.h"
    "${LUAJIT_SOURCE_DIR}/src/lualib.h"
    "${LUAJIT_SOURCE_DIR}/src/lauxlib.h"
    "${LUAJIT_SOURCE_DIR}/src/luajit.h"
    "${LUAJIT_SOURCE_DIR}/src/lua.hpp"
    DESTINATION include/luajit)
