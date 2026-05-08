#!/bin/zsh
set -euo pipefail

rck="${RCK_HELPER:-}"
if [[ -z "$rck" ]]; then
  rck="$HOME/.rightclickkit/bin/rck"
fi

"$rck" report storage-analysis "$@"