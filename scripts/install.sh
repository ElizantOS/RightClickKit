#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUPPORT_DIR="$HOME/.rightclickkit"
BIN_DIR="$SUPPORT_DIR/bin"
CLI_LINK_RECORD="$SUPPORT_DIR/cli-link.txt"
APP_DIR="$HOME/Applications/RightClickKit.app"
AGENT_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitAgent.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
AGENT_LAUNCH_AGENT="$LAUNCH_AGENTS_DIR/com.elizantos.RightClickKit.agent.plist"
STORAGE_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitStorageView.app"
TREE_APP_DIR="$APP_DIR/Contents/Helpers/RightClickKitTreeView.app"
CODEX_APP_ASAR="/Applications/Codex.app/Contents/Resources/app.asar"
FIREBALL_ASSET="webview/assets/fireball-spritesheet-v4-BtU8R9Qp.webp"
FIREBALL_RESOURCE="fireball-spritesheet-v4-BtU8R9Qp.webp"
DIMO_RESOURCE="rck-dimo-spritesheet.webp"
DIMO_ASSET="assets/pets/rck-dimo/$DIMO_RESOURCE"

path_contains() {
  [[ ":$PATH:" == *":$1:"* ]]
}

cleanup_cli_link_record() {
  if [[ -f "$CLI_LINK_RECORD" ]]; then
    local recorded
    recorded="$(<"$CLI_LINK_RECORD")"
    if [[ -n "$recorded" && -L "$recorded" ]]; then
      rm -f "$recorded"
    fi
    rm -f "$CLI_LINK_RECORD"
  fi
}

find_cli_link_path() {
  local preferred
  for preferred in "$HOME/.local/bin" "$HOME/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
    if path_contains "$preferred"; then
      mkdir -p "$preferred" 2>/dev/null || true
      if [[ -d "$preferred" && -w "$preferred" ]]; then
        printf '%s\n' "$preferred/rck"
        return 0
      fi
    fi
  done

  local entry
  for entry in "${(@s/:/)PATH}"; do
    [[ -z "$entry" ]] && continue
    [[ "$entry" == "$BIN_DIR" ]] && continue
    case "$entry" in
      "$HOME/.codex/"*|"$HOME/.antigravity/"*|"/Applications/"*|"/System/"*|"/usr/bin"|"/bin"|"/usr/sbin"|"/sbin")
        continue
        ;;
    esac
    if [[ "$entry" == "$HOME/"* ]]; then
      mkdir -p "$entry" 2>/dev/null || true
    fi
    if [[ -d "$entry" && -w "$entry" ]]; then
      printf '%s\n' "$entry/rck"
      return 0
    fi
  done
  return 1
}

install_cli_link() {
  cleanup_cli_link_record

  local link_path
  link_path="$(find_cli_link_path || true)"
  if [[ -z "$link_path" ]]; then
    echo "Shell command: add $BIN_DIR to PATH to run 'rck' directly"
    return
  fi

  if [[ -e "$link_path" && ! -L "$link_path" ]]; then
    echo "Shell command skipped: $link_path already exists"
    echo "Direct CLI: $BIN_DIR/rck"
    return
  fi

  ln -sfn "$BIN_DIR/rck" "$link_path"
  printf '%s\n' "$link_path" > "$CLI_LINK_RECORD"
  echo "Shell command: $link_path"
}

mkdir -p "$BIN_DIR" "$LAUNCH_AGENTS_DIR" "$HOME/Library/Logs/RightClickKit" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$AGENT_APP_DIR/Contents/MacOS" "$AGENT_APP_DIR/Contents/Resources"
mkdir -p "$STORAGE_APP_DIR/Contents/MacOS" "$STORAGE_APP_DIR/Contents/Resources"
mkdir -p "$TREE_APP_DIR/Contents/MacOS" "$TREE_APP_DIR/Contents/Resources"

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
install -m 755 "$BUILD_DIR/RightClickKitAgent" "$BIN_DIR/RightClickKitAgent"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$BIN_DIR/RightClickKitStorageView"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$BIN_DIR/RightClickKitTreeView"
install_cli_link
install -m 755 "$BUILD_DIR/RightClickKitApp" "$APP_DIR/Contents/MacOS/RightClickKitApp"
install -m 755 "$BUILD_DIR/rck" "$APP_DIR/Contents/Resources/rck"
install -m 755 "$BUILD_DIR/RightClickKitAgent" "$APP_DIR/Contents/Resources/RightClickKitAgent"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$APP_DIR/Contents/Resources/RightClickKitStorageView"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$APP_DIR/Contents/Resources/RightClickKitTreeView"
if [[ -f "$CODEX_APP_ASAR" ]] && command -v npx >/dev/null 2>&1; then
  (
    cd "$APP_DIR/Contents/Resources"
    npx --yes asar extract-file "$CODEX_APP_ASAR" "$FIREBALL_ASSET" >/dev/null 2>&1 || true
  )
fi
install -m 644 "$REPO_ROOT/$DIMO_ASSET" "$APP_DIR/Contents/Resources/$DIMO_RESOURCE"
install -m 644 "$REPO_ROOT/Sources/RightClickKitApp/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf '%s\n' "$REPO_ROOT" > "$APP_DIR/Contents/Resources/repository-root.txt"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitAgent" "$AGENT_APP_DIR/Contents/MacOS/RightClickKitAgent"
install -m 644 "$REPO_ROOT/Sources/RightClickKitAgent/Info.plist" "$AGENT_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$AGENT_APP_DIR/Contents/Resources/AppIcon.icns"
install -m 644 "$REPO_ROOT/$DIMO_ASSET" "$AGENT_APP_DIR/Contents/Resources/$DIMO_RESOURCE"
if [[ -f "$APP_DIR/Contents/Resources/$FIREBALL_RESOURCE" ]]; then
  install -m 644 "$APP_DIR/Contents/Resources/$FIREBALL_RESOURCE" "$AGENT_APP_DIR/Contents/Resources/$FIREBALL_RESOURCE"
fi
printf 'APPL????' > "$AGENT_APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitStorageView" "$STORAGE_APP_DIR/Contents/MacOS/RightClickKitStorageView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitStorageView/Info.plist" "$STORAGE_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$STORAGE_APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STORAGE_APP_DIR/Contents/PkgInfo"
install -m 755 "$BUILD_DIR/RightClickKitTreeView" "$TREE_APP_DIR/Contents/MacOS/RightClickKitTreeView"
install -m 644 "$REPO_ROOT/Sources/RightClickKitTreeView/Info.plist" "$TREE_APP_DIR/Contents/Info.plist"
install -m 644 "$REPO_ROOT/assets/AppIcon.icns" "$TREE_APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$TREE_APP_DIR/Contents/PkgInfo"
codesign --force --deep --sign - "$AGENT_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$STORAGE_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$TREE_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

"$BIN_DIR/rck" install --repo "$REPO_ROOT" --rck "$BIN_DIR/rck"

cat > "$AGENT_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.elizantos.RightClickKit.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$AGENT_APP_DIR/Contents/MacOS/RightClickKitAgent</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/RightClickKit/agent-launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/RightClickKit/agent-launchd.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$AGENT_LAUNCH_AGENT" >/dev/null 2>&1 || true
pkill -f "$AGENT_APP_DIR/Contents/MacOS/RightClickKitAgent" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$AGENT_LAUNCH_AGENT" >/dev/null 2>&1 || true

echo "RightClickKit installed."
echo "CLI: $BIN_DIR/rck"
echo "App: $APP_DIR"
echo "Agent: $AGENT_APP_DIR"
echo "Login Agent: $AGENT_LAUNCH_AGENT"
echo "Finder: right-click a file or folder -> Quick Actions/Services -> RightClickKit actions"
