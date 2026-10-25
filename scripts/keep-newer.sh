#!/usr/bin/env bash
# keep-newer.sh OLD NEW: after a bump rewrote NEW, put back any `name = "version"` line whose new
# version is older than in OLD. Waiting for releases to age (update.yml's minimum release age)
# can pick an older release than one already pinned; updates should never go backwards.
set -euo pipefail

old="$1" new="$2"

older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

while IFS= read -r line; do
  [[ "$line" =~ ^([^=#[:space:]][^=]*[^=[:space:]])[[:space:]]*=[[:space:]]*\"([^\"]+)\"$ ]] || continue
  key="${BASH_REMATCH[1]}" was="${BASH_REMATCH[2]}"
  now="$(grep -F -- "$key = " "$new" | head -1 | sed -E 's/.*= *"([^"]+)".*/\1/')" || continue
  if [ -n "$now" ] && older "$now" "$was"; then
    echo "keeping $key at $was (bump picked older $now)"
    # replace the whole line, matching the key literally
    awk -v k="$key = " -v l="$line" 'index($0, k) == 1 && !done { print l; done = 1; next } { print }' "$new" >"$new.tmp"
    mv "$new.tmp" "$new"
  fi
done <"$old"
