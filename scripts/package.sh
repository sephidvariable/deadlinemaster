#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--distribution" ]]; then
  echo "Distribution blocked: complete the corresponding-source and license review in docs/FFMPEG.md first." >&2
  exit 1
fi
python3 scripts/bundle-ffmpeg.py
./scripts/dev.sh release
app="$PWD/build/Deadline Master.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/AppIcon.iconset
binary_dir=$(CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" swift build -c release --scratch-path .build --cache-path .cache/swiftpm --arch arm64 --show-bin-path)
cp "$binary_dir/DeadlineMaster" "$app/Contents/MacOS/DeadlineMaster"
cp Resources/Info.plist "$app/Contents/Info.plist"
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" swift scripts/make-icon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
ditto build/FFmpegFull "$app/Contents/Resources/FFmpegFull"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
