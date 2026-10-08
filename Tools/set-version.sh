#!/bin/zsh

set -euo pipefail

if (( $# != 2 )); then
    print -u2 "Usage: $0 <version> <build-number>"
    exit 1
fi

version="$1"
build="$2"

if ! print -r -- "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    print -u2 "Version must use MAJOR.MINOR.PATCH format."
    exit 1
fi

if ! print -r -- "$build" | grep -Eq '^[1-9][0-9]*$'; then
    print -u2 "Build number must be a positive integer."
    exit 1
fi

root="${0:A:h:h}"
plist="$root/App/Info.plist"

if [[ $(grep -c '<key>CFBundleShortVersionString</key>' "$plist") -ne 1 ]] ||
   [[ $(grep -c '<key>CFBundleVersion</key>' "$plist") -ne 1 ]]; then
    print -u2 "Could not find unique bundle version keys in $plist."
    exit 1
fi

sed -i '' "/<key>CFBundleShortVersionString<\\/key>/{n;s#<string>[^<]*</string>#<string>$version</string>#;}" "$plist"
sed -i '' "/<key>CFBundleVersion<\\/key>/{n;s#<string>[^<]*</string>#<string>$build</string>#;}" "$plist"
plutil -lint "$plist"

print "Set Unlocked Time to version $version ($build)."
