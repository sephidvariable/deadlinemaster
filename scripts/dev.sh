#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache/clang .cache/swiftpm .build
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang"
case "${1:-build}" in
  build) swift build --scratch-path .build --cache-path .cache/swiftpm --arch arm64 ;;
  test) swift test --scratch-path .build --cache-path .cache/swiftpm --arch arm64 ;;
  release) swift build -c release --scratch-path .build --cache-path .cache/swiftpm --arch arm64 ;;
  *) echo "Usage: $0 build|test|release"; exit 2 ;;
esac
