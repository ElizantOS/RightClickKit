#!/bin/zsh
set -euo pipefail

SUPPORT_DIR="$HOME/.rightclickkit"
BIN_DIR="$SUPPORT_DIR/bin"
CLI_LINK_RECORD="$SUPPORT_DIR/cli-link.txt"
APP_DIR="$HOME/Applications/RightClickKit.app"
RCK="$BIN_DIR/rck"

cleanup_cli_link() {
  if [[ -f "$CLI_LINK_RECORD" ]]; then
    local recorded
    recorded="$(<"$CLI_LINK_RECORD")"
    if [[ -n "$recorded" && -L "$recorded" ]]; then
      rm -f "$recorded"
    fi
    rm -f "$CLI_LINK_RECORD"
  fi

  local candidate
  for candidate in "$HOME/.local/bin/rck" "$HOME/bin/rck" "/opt/homebrew/bin/rck" "/usr/local/bin/rck"; do
    if [[ -L "$candidate" ]] && [[ "$(readlink "$candidate")" == "$BIN_DIR/rck" ]]; then
      rm -f "$candidate"
    fi
  done
}

if [[ -x "$RCK" ]]; then
  "$RCK" uninstall || true
else
  find "$HOME/Library/Services" -maxdepth 1 -name "*.workflow" -print0 2>/dev/null |
    while IFS= read -r -d '' workflow; do
      info="$workflow/Contents/Info.plist"
      if [[ -f "$info" ]] && /usr/libexec/PlistBuddy -c "Print :RightClickKitManaged" "$info" 2>/dev/null | grep -q '^true$'; then
        rm -rf "$workflow"
        echo "Removed $workflow"
      fi
    done
  /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  killall Finder 2>/dev/null || true
fi

rm -rf "$APP_DIR"
rm -f "$BIN_DIR/rck"
cleanup_cli_link

echo "RightClickKit uninstalled."
echo "Logs are kept in: $HOME/Library/Logs/RightClickKit"
echo "Service source files are kept in this repository."
