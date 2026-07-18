vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO microsoft/Detours
    REF v4.0.1
    SHA512 0a9c21b8222329add2de190d2e94d99195dfa55de5a914b75d380ffe0fb787b12e016d0723ca821001af0168fd1643ffd2455298bf3de5fdc155b3393a3ccc87
    HEAD_REF master
    PATCHES
        find-jmp-bounds-arm64.patch
)

# Upstream Detours has no CMake build (only an NMake Makefile, which vcpkg
# cannot run on a Linux host). Drop in a CMakeLists so we can build with the
# chainloaded clang-cl toolchain.
file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}/src")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/src"
)
vcpkg_cmake_install()

include(CMakePackageConfigHelpers)
configure_package_config_file(
    "${CMAKE_CURRENT_LIST_DIR}/detours-config.cmake.in"
    "${CURRENT_PACKAGES_DIR}/share/${PORT}/detours-config.cmake"
    INSTALL_DESTINATION "share/${PORT}"
)
write_basic_package_version_file(
    "${CURRENT_PACKAGES_DIR}/share/${PORT}/detours-config-version.cmake"
    VERSION 4.0.1
    COMPATIBILITY SameMajorVersion
)

file(INSTALL "${SOURCE_PATH}/LICENSE.md" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
