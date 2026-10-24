#!/bin/bash
# Builds HaluMe.app into ./build and, with --install, copies it to ~/Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product HaluMe
BIN="$(swift build -c release --show-bin-path)"
APP="build/HaluMe.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HaluMe" "$APP/Contents/MacOS/HaluMe"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# shortcut: Halu's icon as a placeholder until HaluMe has its own.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x HaluMe || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/HaluMe.app"
    cp -R "$APP" "$HOME/Applications/HaluMe.app"
    open "$HOME/Applications/HaluMe.app"
    echo "Installed to ~/Applications/HaluMe.app"
fi
