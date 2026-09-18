#!/bin/bash
# Compila Island Effect y arma el bundle .app.
#   ./build.sh          -> compila en ./build/Island Effect.app
#   ./build.sh --run    -> compila, reemplaza la instancia corriendo y la lanza
#   ./build.sh --install-> además copia la app a /Applications
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Island Effect"
BUNDLE_ID="com.j0kz.IslandEffect"
VERSION="1.0.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compilando (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/IslandEffect"

echo "▸ Armando el bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IslandEffect"

# Localizaciones
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# Icono
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift tools/MakeIcon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "  (icono omitido)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>IslandEffect</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Island Effect asks Music and Spotify what is playing, so it can show and control it.</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 j0KZ · MIT License</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>es</string></array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>CFBundleURLSchemes</key><array><string>islandeffect</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ Firmando (ad-hoc)…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (sin firma)"

echo "✓ Listo: $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Instalando en /Applications…"
    pkill -f "Island Effect.app/Contents/MacOS/IslandEffect" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    open "/Applications/$APP_NAME.app"
    echo "✓ Instalada y corriendo desde /Applications"
elif [[ "${1:-}" == "--run" ]]; then
    pkill -f "$APP_NAME.app/Contents/MacOS/IslandEffect" 2>/dev/null || true
    sleep 0.5
    open "$APP"
    echo "✓ Corriendo"
fi
