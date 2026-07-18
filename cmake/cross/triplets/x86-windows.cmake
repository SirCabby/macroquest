# Overlay triplet: x86-windows (dynamic) for the Linux cross build.
# Only used for download-only redistributable ports (dxsdk-d3dx provides
# D3DX9d_43.dll in its dynamic-linkage layout); nothing is compiled with it.
set(VCPKG_TARGET_ARCHITECTURE x86)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../clang-cl-win32.toolchain.cmake")

set(VCPKG_ENV_PASSTHROUGH PATH HOME MQ_WINSYSROOT)
set(VCPKG_BUILD_TYPE release)
