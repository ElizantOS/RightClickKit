#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/RightClickKitPreview.app"
STORAGE_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitStorageView.app"
TREE_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitTreeView.app"
SUPPORT_DIR="$HOME/.rightclickkit"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$STORAGE_APP_DIR/Contents/MacOS" "$STORAGE_APP_DIR/Contents/Resources"
mkdir -p "$TREE_APP_DIR/Contents/MacOS" "$TREE_APP_DIR/Contents/Resources"

cd "$REPO_ROOT"
SWIFT_BUILD_ARGS=(
  --disable-sandbox
  --disable-build-manifest-caching
  --cache-path .build/cache
  --scratch-path .build/swiftpm
)
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

install -m 755 "$BUILD_DIR/RightClickKitApp" "$APP_DIR/Contents/MacOS/RightClickKitApp"
install -m 755 "$BUILD_DIR/rck" "$APP_DIR/Contents/Resources/rck"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$APP_DIR/Contents/Resources/RightClickKitStorageView"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$APP_DIR/Contents/Resources/RightClickKitTreeView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitApp/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf '%s\n' "$REPO_ROOT" > "$APP_DIR/Contents/Resources/repository-root.txt"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$STORAGE_APP_DIR/Contents/MacOS/RightClickKitStorageView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitStorageView/Info.plist" "$STORAGE_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$STORAGE_APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STORAGE_APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$TREE_APP_DIR/Contents/MacOS/RightClickKitTreeView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitTreeView/Info.plist" "$TREE_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$TREE_APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$TREE_APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$STORAGE_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$TREE_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

mkdir -p "$SUPPORT_DIR/bin"
install -m 755 "$BUILD_DIR/rck" "$SUPPORT_DIR/bin/rck"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$SUPPORT_DIR/bin/RightClickKitStorageView"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$SUPPORT_DIR/bin/RightClickKitTreeView"
cat > "$SUPPORT_DIR/config.json" <<EOF_CONFIG
{
  "repositoryRoot" : "$REPO_ROOT",
  "rckPath" : "$SUPPORT_DIR/bin/rck"
}
EOF_CONFIG

echo "Preview app updated: $APP_DIR"
echo "Open it from Finder or run: open ~/Applications/RightClickKitPreview.app"
