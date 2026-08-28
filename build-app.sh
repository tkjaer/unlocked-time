#!/bin/zsh

set -euo pipefail

root="${0:A:h}"
app="$root/dist/Unlocked Time.app"

cd "$root"
swift build -c release

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/UnlockedTime" "$app/Contents/MacOS/UnlockedTime"
cp "$root/App/Info.plist" "$app/Contents/Info.plist"
cp "$root/App/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"

print "Built $app"