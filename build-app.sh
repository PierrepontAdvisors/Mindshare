#!/bin/bash
# Builds Mindshare.app with the Command Line Tools; full Xcode isn't needed.
set -euo pipefail
cd "$(dirname "$0")"

swift run CoreCheck
swift build -c release --product Mindshare --arch arm64
swift build -c release --product Mindshare --arch x86_64

app=build/Mindshare.app
rm -rf build
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# One app that runs on both Apple Silicon and Intel Macs.
lipo -create \
    .build/arm64-apple-macosx/release/Mindshare \
    .build/x86_64-apple-macosx/release/Mindshare \
    -output "$app/Contents/MacOS/Mindshare"

# Debug symbols hold the full build path, including your username. Never ship them.
strip -S -x "$app/Contents/MacOS/Mindshare"
# Only system libraries are used, so these search paths do nothing except widen what could be loaded.
install_name_tool -delete_rpath @loader_path "$app/Contents/MacOS/Mindshare"
install_name_tool -delete_rpath "$(xcode-select -p)/usr/lib/swift-6.2/macosx" "$app/Contents/MacOS/Mindshare" 2>/dev/null || true

cp Info.plist "$app/Contents/"
cp Assets/AppIcon.icns "$app/Contents/Resources/"
# Hardened runtime blocks code injection, and works without a paid certificate.
codesign --force --options runtime --sign - "$app"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$app" build/Mindshare.zip
echo "Built $app and build/Mindshare.zip"
