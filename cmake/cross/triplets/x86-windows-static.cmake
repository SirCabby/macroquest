# Overlay triplet: build x86-windows-static ports on Linux with clang-cl.
# Selected via VCPKG_OVERLAY_TRIPLETS when MQ_CROSS_LINUX is enabled.
set(VCPKG_TARGET_ARCHITECTURE x86)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

# Cross-compile from Linux via the clang-cl/lld-link chainload toolchain (which
# sets CMAKE_SYSTEM_NAME=Windows itself). We deliberately DO NOT set
# VCPKG_CMAKE_SYSTEM_NAME: vcpkg only treats an empty value as "native Windows",
# and that is what keeps VCPKG_TARGET_IS_WINDOWS true — ports like sqlite3 key
# their Windows vs. POSIX code paths off it, and the `supports: windows`
# expressions then evaluate correctly (no --allow-unsupported needed).
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../clang-cl-win32.toolchain.cmake")

set(VCPKG_ENV_PASSTHROUGH PATH HOME MQ_WINSYSROOT)
set(VCPKG_BUILD_TYPE release)
