#!/bin/bash
# GeneralsX @feature iOS port 11/11/2026 Builds the external display harness (harness.c) for the iOS
# Simulator from a configured and built simulator tree (the ios-vulkan-sim preset of
# CMakeUserPresets.json, built with `cmake --build build/ios-vulkan-sim --target z_generals`), so it
# uses that build's patched SDL3 and launcher library. See README.md.
#
# Usage: build-harness.sh [build dir] [output dir]   (defaults: build/ios-vulkan-sim, build/ext-harness)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../../.." && pwd)"
BUILD="${1:-${ROOT}/build/ios-vulkan-sim}"
OUT="${2:-${ROOT}/build/ext-harness}"
APP="${OUT}/GXExternalDisplayHarness.app"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SWIFTC="$(xcrun --sdk iphonesimulator --find swiftc)"
TOOLCHAIN_USR="$(cd "$(dirname "${SWIFTC}")/.." && pwd)"
GXL="${BUILD}/gxlauncher/out/Products/Release-iphonesimulator"
SDL_SRC="${BUILD}/_deps/sdl3-src"
SDL_LIB="${BUILD}/_deps/sdl3-build/libSDL3.0.dylib"

for f in "${GXL}/libGXLauncher.a" "${SDL_LIB}"; do
    [[ -f "$f" ]] || { echo "ERROR: $f not found: build the simulator tree first"; exit 1; }
done

rm -rf "${APP}"
mkdir -p "${APP}/Frameworks"
clang -target arm64-apple-ios17.0-simulator -isysroot "${SDK}" -O1 -g \
    -I"${SDL_SRC}/include" -I"${ROOT}/ios/Launcher/GXLauncher/include" \
    "${HERE}/harness.c" -o "${APP}/GXExternalDisplayHarness" \
    "${SDL_LIB}" \
    -Wl,-force_load,"${GXL}/libGXLauncher.a" \
    -L"${SDK}/usr/lib/swift" -L"${TOOLCHAIN_USR}/lib/swift/iphonesimulator" \
    -Wl,-rpath,/usr/lib/swift -Wl,-rpath,@executable_path/Frameworks
cp "${SDL_LIB}" "${APP}/Frameworks/"
install_name_tool -change "$(otool -L "${APP}/GXExternalDisplayHarness" | awk '/libSDL3/ {print $1; exit}')" \
    @rpath/libSDL3.0.dylib "${APP}/GXExternalDisplayHarness"
[[ -d "${GXL}/GXLauncher_GXLauncher.bundle" ]] && cp -R "${GXL}/GXLauncher_GXLauncher.bundle" "${APP}/"
cp "${HERE}/Info.plist" "${APP}/Info.plist"
codesign --force --sign - "${APP}/Frameworks/libSDL3.0.dylib"
codesign --force --sign - "${APP}"
echo "${APP}"
