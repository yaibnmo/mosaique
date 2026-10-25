#!/bin/zsh
# Builds Mosaïque.app (universal: Apple Silicon + Intel) into dist/, runs the model tests and zips the app.
#   zsh build.sh                          ad hoc signature (fine for personal use)
#   MOSAIQUE_SIGN="Apple Development: …" zsh build.sh   signs with your certificate, so macOS keeps
#                                         the Accessibility permission across rebuilds
set -euo pipefail
cd "${0:A:h}"
VERSION=1.0.0
APP=dist/Mosaique.app
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon -framework ServiceManagement)
rm -rf dist && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources dist/obj

echo "› Icône"
xcrun swiftc -O -parse-as-library Sources/IconStyles.swift Tools/MakeAppIcon.swift -o dist/obj/make-icon -framework AppKit
dist/obj/make-icon dist/obj/AppIcon.iconset
iconutil -c icns dist/obj/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns

echo "› Compilation (arm64 + x86_64)"
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target $arch-apple-macosx15.0 Sources/*.swift -o dist/obj/Mosaique-$arch $FRAMEWORKS
done
lipo -create dist/obj/Mosaique-arm64 dist/obj/Mosaique-x86_64 -output $APP/Contents/MacOS/Mosaique

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.yaibnmo.mosaique</string>
<key>CFBundleName</key><string>Mosaïque</string>
<key>CFBundleDisplayName</key><string>Mosaïque</string>
<key>CFBundleExecutable</key><string>Mosaique</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint $APP/Contents/Info.plist >/dev/null

echo "› Signature"
codesign --force --sign "${MOSAIQUE_SIGN:--}" --timestamp=none $APP
codesign --verify --strict $APP

echo "› Tests"
xcrun swiftc -parse-as-library Sources/Layout.swift Tests/LayoutTests.swift -o dist/obj/layout-tests
dist/obj/layout-tests
xcrun swiftc -parse-as-library Sources/Overlays.swift Sources/Layout.swift Tests/TabBarCheck.swift -o dist/obj/tab-bar-check -framework AppKit
dist/obj/tab-bar-check | tail -1

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent $APP dist/Mosaique.zip
echo "✓ dist/Mosaique.app et dist/Mosaique.zip"
