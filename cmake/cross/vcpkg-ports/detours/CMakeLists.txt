cmake_minimum_required(VERSION 3.20)
project(detours CXX)

# Microsoft Detours 4.0.1 built as a static library. This mirrors the object
# list in Detours' own src/Makefile, but drives it through CMake/clang-cl so it
# can be produced on a Linux host (upstream only ships an NMake makefile).

add_library(detours STATIC
    detours.cpp
    modules.cpp
    disasm.cpp
    image.cpp
    creatwth.cpp
    disolx86.cpp
    disolx64.cpp
    disolia64.cpp
    disolarm.cpp
    disolarm64.cpp
)

target_compile_definitions(detours PRIVATE
    WIN32_LEAN_AND_MEAN
    _WIN32_WINNT=0x0501
)

if(MSVC)
    # Detours' Makefile uses /W4 /WX /Gy /Zl /Od. Drop /WX (clang-cl surfaces
    # different warnings) and keep the rest of the intent.
    target_compile_options(detours PRIVATE /W0 /Gy /Zl /Od)
endif()

set_target_properties(detours PROPERTIES OUTPUT_NAME "detours")

install(TARGETS detours ARCHIVE DESTINATION lib)
install(FILES detours.h detver.h DESTINATION include/detours)
