#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="$HOME/.rightclickkit"
BIN_DIR="$SUPPORT_DIR/bin"
APP_DIR="$HOME/Applications/RightClickKit.app"
STORAGE_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitStorageView.app"

mkdir -p "$BIN_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$STORAGE_APP_DIR/Contents/MacOS" "$STORAGE_APP_DIR/Contents/Resources"

cd "$REPO_ROOT"
SWIFT_BUILD_ARGS=(
  --disable-sandbox
  --disable-build-manifest-caching
  --cache-path .build/cache
  --scratch-path .build/swiftpm
  -c release
)
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

install -m 755 "$BUILD_DIR/rck" "$BIN_DIR/rck"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$BIN_DIR/RightClickKitStorageView"
install -m 755 "$BUILD_DIR/RightClickKitApp" "$APP_DIR/Contents/MacOS/RightClickKitApp"
install -m 755 "$BUILD_DIR/rck" "$APP_DIR/Contents/Resources/rck"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$APP_DIR/Contents/Resources/RightClickKitStorageView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitApp/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf '%s\n' "$REPO_ROOT" > "$APP_DIR/Contents/Resources/repository-root.txt"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$STORAGE_APP_DIR/Contents/MacOS/RightClickKitStorageView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitStorageView/Info.plist" "$STORAGE_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$STORAGE_APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STORAGE_APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$STORAGE_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

"$BIN_DIR/rck" install --repo "$REPO_ROOT" --rck "$BIN_DIR/rck"

echo "RightClickKit installed."
echo "CLI: $BIN_DIR/rck"
echo "App: $APP_DIR"
echo "Finder: right-click a file or folder -> Quick Actions/Services -> RightClickKit actions"
