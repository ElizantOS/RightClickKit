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

TREE_REPORT="$("$RCK" report directory-tree --no-open "$REPO_ROOT/services" | sed 's/^Report: //')"
test -s "$TREE_REPORT"
grep -q 'show-directory-tree' "$TREE_REPORT"

STORAGE_REPORT="$("$RCK" report storage-analysis --no-open "$REPO_ROOT/services" | sed 's/^Report: //')"
test -s "$STORAGE_REPORT"
grep -q '"generatedAt"' "$STORAGE_REPORT"
grep -q '"root"' "$STORAGE_REPORT"
grep -q '"children"' "$STORAGE_REPORT"
test -x "$BUILD_DIR/RightClickKitStorageView"
test -x "$BUILD_DIR/RightClickKitTreeView"

RIGHTCLICKKIT_HOME="$TMP_HOME" RIGHTCLICKKIT_SKIP_REFRESH=1 "$RCK" install --repo "$REPO_ROOT" --rck "$RCK"

for title in "Analyze Storage" "Open in Code" "Show Directory Tree"; do
  WORKFLOW="$TMP_HOME/Library/Services/$title.workflow"
  INFO="$WORKFLOW/Contents/Info.plist"
  DOCUMENT="$WORKFLOW/Contents/Resources/document.wflow"

  test -d "$WORKFLOW"
  plutil -lint "$INFO" "$DOCUMENT" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :RightClickKitManaged" "$INFO" | grep -q '^true$'
done

RIGHTCLICKKIT_HOME="$TMP_HOME" RIGHTCLICKKIT_SKIP_REFRESH=1 "$RCK" uninstall
test ! -e "$TMP_HOME/Library/Services/Open in Code.workflow"
test ! -e "$TMP_HOME/Library/Services/Show Directory Tree.workflow"
test ! -e "$TMP_HOME/Library/Services/Analyze Storage.workflow"

echo "Smoke test passed."
