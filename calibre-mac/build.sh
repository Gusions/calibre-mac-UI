#!/bin/zsh
# Compila l'app (universale arm64 + x86_64) e crea "Calibre Mac.app". Non richiede Xcode completo.
set -e
cd "$(dirname "$0")"
APP="build/Calibre Mac.app"
rm -rf "$APP" build/tmp; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp
SDK=$(xcrun --show-sdk-path)
for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 -sdk "$SDK" -target $ARCH-apple-macosx26.0 \
    Sources/CalibreMac/*.swift -o build/tmp/CalibreMac-$ARCH
done
lipo -create build/tmp/CalibreMac-* -output "$APP/Contents/MacOS/CalibreMac"

# Icona
swiftc -sdk "$SDK" tools/make_icon.swift -o build/tmp/make_icon
build/tmp/make_icon build/tmp/icon1024.png
ICONSET=build/tmp/AppIcon.iconset; mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s build/tmp/icon1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/tmp/icon1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Calibre Mac</string>
<key>CFBundleDisplayName</key><string>Calibre Mac</string>
<key>CFBundleIdentifier</key><string>app.calibremac</string>
<key>CFBundleExecutable</key><string>CalibreMac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>E-book</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSItemContentTypes</key><array><string>org.idpf.epub-container</string><string>com.adobe.pdf</string></array></dict></array>
</dict></plist>
P
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
rm -rf build/tmp
echo "Creato: $APP"
