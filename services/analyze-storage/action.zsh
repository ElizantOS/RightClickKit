#!/bin/zsh
set -euo pipefail

rck="${RCK_HELPER:-$HOME/.rightclickkit/bin/rck}"
if [[ ! -x "$rck" ]]; then
  echo "missing rck executable: $rck" >&2
  exit 127
fi

"$rck" action run 'storage-analysis' "$@"