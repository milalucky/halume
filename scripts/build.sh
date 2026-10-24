#!/bin/bash
# Builds Halu Money.app into ./build and, with --install, copies it to ~/Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product HaluMoney
BIN="$(swift build -c release --show-bin-path)"
APP="build/Halu Money.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HaluMoney" "$APP/Contents/MacOS/HaluMoney"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# shortcut: Halu's icon as a placeholder until Halu Money has its own.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x HaluMoney || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Halu Money.app"
    cp -R "$APP" "$HOME/Applications/Halu Money.app"
    open "$HOME/Applications/Halu Money.app"
    echo "Installed to ~/Applications/Halu Money.app"
fi
