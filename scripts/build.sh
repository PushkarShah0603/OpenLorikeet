#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$PWD/.build/swiftpm"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
build_options=(--scratch-path "$build_dir" --build-system native -debug-info-format none --disable-sandbox
    --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security")
swift build "${build_options[@]}" --product OpenLorikeet -c release
bin_dir=$(swift build "${build_options[@]}" -c release --show-bin-path)
final_app="$PWD/dist/OpenLorikeet.app"
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/.app-build.XXXXXX")
app="$staging/OpenLorikeet.app"

cleanup() {
    if [[ -e "$staging/previous.app" && ! -e "$final_app" ]]; then
        if ! mv "$staging/previous.app" "$final_app"; then
            printf 'Previous build retained at %s\n' "$staging/previous.app" >&2
            return
        fi
    fi
    /bin/rm -r -- "$staging"
}
trap cleanup EXIT

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/OpenLorikeet" "$app/Contents/MacOS/OpenLorikeet"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift "$app/Contents/Resources" docs/assets/lorikeet.png
plutil -lint "$app/Contents/Info.plist"
if [[ -n "${LORIKEET_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$LORIKEET_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
if [[ -e "$final_app" ]]; then
    mv "$final_app" "$staging/previous.app"
fi
mv "$app" "$final_app"
printf 'Built %s\n' "$final_app"
