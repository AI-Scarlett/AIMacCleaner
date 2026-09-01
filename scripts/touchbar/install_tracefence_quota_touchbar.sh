#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_script="$script_dir/tracefence-quota-touchbar-read.mjs"
target_dir="$HOME/Library/Application Support/TraceFence/TouchBar"
target_script="$target_dir/tracefence-quota-touchbar-read.mjs"

[[ -f "$source_script" ]] || {
  echo "Missing Touch Bar reader: $source_script" >&2
  exit 1
}

install -d -m 700 "$target_dir"
install -m 700 "$source_script" "$target_script"

printf 'Installed TraceFence Touch Bar reader:\n%s\n\n' "$target_script"
printf 'In BetterTouchTool, add a global Touch Bar Shell Script Widget with:\n'
printf 'node %q\n' "$target_script"
printf 'Set the widget refresh interval to 15 seconds.\n'
