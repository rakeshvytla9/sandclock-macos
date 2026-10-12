#!/bin/bash
set -euo pipefail

SANDCLOCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDCLOCK_ARCH="${1:-$(uname -m)}"
case "$SANDCLOCK_ARCH" in
  arm64|x86_64) ;;
  *) echo "Usage: scripts/build.sh [arm64|x86_64]" >&2; exit 1 ;;
esac
cd "$SANDCLOCK_ROOT"

SANDCLOCK_APP="dist/Sandclock.app"
mkdir -p "$SANDCLOCK_APP/Contents/MacOS" "$SANDCLOCK_APP/Contents/Resources"
cp Resources/Info.plist "$SANDCLOCK_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$SANDCLOCK_APP/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -target "$SANDCLOCK_ARCH-apple-macosx13.0" -framework AppKit \
  Source/main.swift -o "$SANDCLOCK_APP/Contents/MacOS/Sandclock"
codesign --force --sign - "$SANDCLOCK_APP"
codesign --verify --deep --strict "$SANDCLOCK_APP"

if [[ "$SANDCLOCK_ARCH" == "$(uname -m)" ]]; then
  "$SANDCLOCK_APP/Contents/MacOS/Sandclock" --self-test
else
  echo "Cross-compiled $SANDCLOCK_ARCH; run --self-test on matching hardware."
fi

ditto -c -k --sequesterRsrc --keepParent "$SANDCLOCK_APP" "dist/Sandclock-macOS-$SANDCLOCK_ARCH.zip"
echo "Built $SANDCLOCK_APP and dist/Sandclock-macOS-$SANDCLOCK_ARCH.zip"
