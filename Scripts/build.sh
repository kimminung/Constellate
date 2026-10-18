#!/bin/zsh
# Usage: Scripts/build.sh [macos|ipad|vision|all]
# Redirects module cache + derived data to a writable location (the default clang cache is not writable in this environment).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="$HOME/Library/Caches/ConstellateBuild"
mkdir -p "$C/ModuleCache" "$C/DerivedData"
build() {
  echo "▶ building $1"
  SWIFTPM_MODULECACHE_OVERRIDE="$C/ModuleCache" xcodebuild -project "$ROOT/Constellate.xcodeproj" -scheme Constellate \
    -destination "$2" -derivedDataPath "$C/DerivedData" -quiet build MODULE_CACHE_DIR="$C/ModuleCache" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning: .*(deprecated|unused)|BUILD" | grep -v "appintentsmetadataprocessor" | head -60
  echo "exit=${pipestatus[1]}"
}
case "${1:-all}" in
  macos)  build macOS 'platform=macOS' ;;
  ipad)   build iPadOS 'generic/platform=iOS Simulator' ;;
  vision) build visionOS 'generic/platform=visionOS Simulator' ;;
  all)    build macOS 'platform=macOS'; build iPadOS 'generic/platform=iOS Simulator'; build visionOS 'generic/platform=visionOS Simulator' ;;
esac
