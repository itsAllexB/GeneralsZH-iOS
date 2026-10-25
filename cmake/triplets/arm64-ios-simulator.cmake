# Overlay triplet for the arm64 iOS Simulator (Apple silicon hosts); same pinning
# as arm64-ios.cmake, against the simulator SDK.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_OSX_DEPLOYMENT_TARGET "16.0")
set(VCPKG_OSX_ARCHITECTURES arm64)
