#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/rightclickkit-smoke.XXXXXX")"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

cd "$REPO_ROOT"
SWIFT_BUILD_ARGS=(
  --disable-sandbox
  --disable-build-manifest-caching
  --cache-path .build/cache
  --scratch-path .build/swiftpm
)
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
RCK="$BUILD_DIR/rck"

RIGHTCLICKKIT_HOME="$TMP_HOME" "$RCK" list --repo "$REPO_ROOT"
RIGHTCLICKKIT_HOME="$TMP_HOME" RIGHTCLICKKIT_SKIP_REFRESH=1 "$RCK" install --repo "$REPO_ROOT" --rck "$RCK"

WORKFLOW="$TMP_HOME/Library/Services/Open in Code.workflow"
INFO="$WORKFLOW/Contents/Info.plist"
DOCUMENT="$WORKFLOW/Contents/Resources/document.wflow"

test -d "$WORKFLOW"
plutil -lint "$INFO" "$DOCUMENT" >/dev/null
/usr/libexec/PlistBuddy -c "Print :RightClickKitManaged" "$INFO" | grep -q '^true$'

RIGHTCLICKKIT_HOME="$TMP_HOME" RIGHTCLICKKIT_SKIP_REFRESH=1 "$RCK" uninstall
test ! -e "$WORKFLOW"

echo "Smoke test passed."
