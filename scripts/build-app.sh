#!/bin/bash
# Builds dist/Wye.app for both Apple Silicon and Intel Macs.
#   --install   also copy it to /Applications on this Mac
#   --dmg       also create dist/Wye.dmg for installing on another Mac
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=false
DMG=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --dmg) DMG=true ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Wye"

APP="dist/Wye.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Wye"

# Icons come straight from the designer's files in design/logo.
mkdir -p "$APP/Contents/Resources"
cp design/logo/wye-menubar.svg "$APP/Contents/Resources/MenuBarIcon.svg"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" design/logo/wye-app.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" design/logo/wye-app.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wye</string>
    <key>CFBundleIdentifier</key><string>local.wye</string>
    <key>CFBundleExecutable</key><string>Wye</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if $DMG; then
    # A disk image showing the app next to a shortcut to Applications: drag one onto the other.
    STAGE="$WORK/Wye"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/Wye.app"
    ln -s /Applications "$STAGE/Applications"
    # Built without mounting a temporary volume: `hdiutil create -srcfolder` does mount one
    # and fails with "Resource busy" whenever something else on the Mac touches it.
    hdiutil makehybrid -quiet -hfs -hfs-volume-name "Wye" -o "$WORK/raw.dmg" "$STAGE"
    hdiutil convert -quiet "$WORK/raw.dmg" -format UDZO -o "$WORK/Wye.dmg"
    mv -f "$WORK/Wye.dmg" dist/Wye.dmg
    echo "Built dist/Wye.dmg"
fi

if $INSTALL; then
    pkill -x Wye 2>/dev/null || true
    rm -rf "/Applications/Wye.app"
    cp -R "$APP" "/Applications/Wye.app"
    open "/Applications/Wye.app"
    echo "Installed and opened /Applications/Wye.app"
fi
