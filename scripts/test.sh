#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$PWD/.build/swiftpm"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift run --scratch-path "$build_dir" --build-system native -debug-info-format none --disable-sandbox \
    --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security" CoreChecks
