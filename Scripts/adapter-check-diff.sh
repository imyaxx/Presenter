#!/usr/bin/env bash
# Compares the current system with an adapter check backup (docs/13-adapter-check.md).
#
# Usage: Scripts/adapter-check-diff.sh <backup directory>
#
# The five action keys must equal keys.tsv exactly; the regular applications with their hidden flags and the displays
# must equal world.json; the wallpaper store must equal the backup copy when compared by
# Scripts/compare-wallpaper-store.swift (independent of the app's inspector; ignores LastUse only).
# Prints every difference and exits 0 only if there is none.
set -euo pipefail
source "$(dirname "$0")/adapter-check-lib.sh"

[[ $# -eq 1 && -f "$1/MANIFEST.json" ]] || { echo "usage: $0 <backup directory with MANIFEST.json>" >&2; exit 2; }
backup="$1"
status=0

if ! diff_output=$(diff <(cat "$backup/keys.tsv") <(read_action_keys)); then
    echo "keys differ (< backup, > now):"
    echo "$diff_output"
    status=1
else
    echo "keys: equal"
fi

current_world="$CHECK_DIR/results/diff-world-$(date -u +%Y%m%dT%H%M%SZ).json"
"$ROOT/Scripts/adapter-check.sh" --result-file "$current_world" world >/dev/null
for field in applications displays; do
    if ! diff_output=$(diff <(jq -S ".$field" "$backup/world.json") <(jq -S ".$field" "$current_world")); then
        echo "$field differ (< backup, > now):"
        echo "$diff_output"
        status=1
    else
        echo "$field: equal"
    fi
done

if swift "$ROOT/Scripts/compare-wallpaper-store.swift" "$backup/wallpaper/Index.plist" "$WALLPAPER_STORE"; then
    echo "wallpaper store: equal (LastUse ignored)"
else
    status=1
fi

exit $status
