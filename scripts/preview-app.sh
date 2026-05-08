#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/RightClickKitPreview.app"
SUPPORT_DIR="$HOME/.rightclickkit"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

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
install -m 644 "$REPO_ROOT/Sources/RightClickKitApp/Info.plist" "$APP_DIR/Contents/Info.plist"
printf '%s\n' "$REPO_ROOT" > "$APP_DIR/Contents/Resources/repository-root.txt"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

mkdir -p "$SUPPORT_DIR/bin"
install -m 755 "$BUILD_DIR/rck" "$SUPPORT_DIR/bin/rck"
cat > "$SUPPORT_DIR/config.json" <<EOF_CONFIG
{
  "repositoryRoot" : "$REPO_ROOT",
  "rckPath" : "$SUPPORT_DIR/bin/rck"
}
EOF_CONFIG

echo "Preview app updated: $APP_DIR"
echo "Open it from Finder or run: open ~/Applications/RightClickKitPreview.app"
