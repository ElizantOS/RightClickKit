#!/bin/zsh
set -euo pipefail

SUPPORT_DIR="$HOME/.rightclickkit"
BIN_DIR="$SUPPORT_DIR/bin"
APP_DIR="$HOME/Applications/RightClickKit.app"
RCK="$BIN_DIR/rck"

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

echo "RightClickKit uninstalled."
echo "Logs are kept in: $HOME/Library/Logs/RightClickKit"
echo "Service source files are kept in this repository."
