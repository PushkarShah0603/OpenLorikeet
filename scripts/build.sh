#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --build-system native -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --product OpenLorikeet -c release
bin_dir=$(swift build --build-system native -debug-info-format none --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -c release --show-bin-path)
app="$PWD/dist/OpenLorikeet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/OpenLorikeet" "$app/Contents/MacOS/OpenLorikeet"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift "$app/Contents/Resources" Resources/AppIcon.png
plutil -lint "$app/Contents/Info.plist"
if [[ -n "${LORIKEET_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$LORIKEET_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
