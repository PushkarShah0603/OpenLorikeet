#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
archive="$PWD/dist/OpenLorikeet-macOS-$(uname -m).zip"
temporary="$PWD/dist/.OpenLorikeet-package-$$.zip"
trap 'rm -f "$temporary"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$PWD/dist/OpenLorikeet.app" "$temporary"
unzip -tq "$temporary"
mv -f "$temporary" "$archive"
printf 'Packaged %s\n' "$archive"
