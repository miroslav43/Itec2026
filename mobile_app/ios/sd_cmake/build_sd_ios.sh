#!/usr/bin/env bash
# Prefer Bash 4+ for mapfile; macOS /bin/bash is 3.2 — avoid mapfile.
# Builds and merges static libraries for stable-diffusion.cpp + sd_native_bridge for iOS.
# Xcode sets PLATFORM_NAME (iphoneos | iphonesimulator) and ARCHS.
set -euo pipefail

# Xcode Run Script phases use a minimal PATH (no Homebrew / Android SDK). Find cmake.
_sd_ensure_cmake_in_path() {
  command -v cmake >/dev/null 2>&1 && return 0
  local d sdk
  for d in /opt/homebrew/bin /usr/local/bin; do
    if [[ -x "$d/cmake" ]]; then
      export PATH="$d:$PATH"
      return 0
    fi
  done
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  if [[ -d "$sdk/cmake" ]]; then
    for d in "$sdk/cmake"/*/bin; do
      if [[ -x "$d/cmake" ]]; then
        export PATH="$d:$PATH"
        return 0
      fi
    done
  fi
  return 1
}
_sd_ensure_cmake_in_path || {
  echo "sd_ios: cmake not found. Install: brew install cmake, or Android SDK CMake (SDK Manager)." >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_IOS="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${ROOT_IOS}/Runner/libs"
BUILD_ROOT="${SCRIPT_DIR}/_build"

PLAT="${PLATFORM_NAME:-iphoneos}"
mkdir -p "$OUT_DIR/$PLAT"

# Xcode passes ARCHS e.g. "arm64" or "arm64 x86_64" — use first architecture
ARCH_CSV="${ARCHS:-arm64}"
FIRST_ARCH="${ARCH_CSV%% *}"

SDK_PATH="$(xcrun --sdk "$PLAT" --show-sdk-path)"

echo "sd_ios: PLATFORM=$PLAT ARCH=$FIRST_ARCH SDK=$SDK_PATH"

rm -rf "$BUILD_ROOT"
cmake -S "$SCRIPT_DIR" -B "$BUILD_ROOT" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
  -DCMAKE_OSX_ARCHITECTURES="$FIRST_ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

cmake --build "$BUILD_ROOT" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

LIBS=()
while IFS= read -r line; do
  LIBS+=("$line")
done < <(find "$BUILD_ROOT" -name "*.a" ! -path "*/CMakeFiles/*" | sort -u)
if [[ ${#LIBS[@]} -eq 0 ]]; then
  echo "sd_ios: no static libraries produced under $BUILD_ROOT" >&2
  exit 1
fi

OUT_A="$OUT_DIR/$PLAT/libsd_ios_complete.a"
rm -f "$OUT_A"
libtool -static -o "$OUT_A" "${LIBS[@]}"
echo "sd_ios: wrote $OUT_A (${#LIBS[@]} archives merged)"
