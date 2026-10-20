#!/usr/bin/env bash
# Takes the backup that every mutating adapter check command requires (docs/13-adapter-check.md).
#
# Usage: Scripts/adapter-check-backup.sh [--screenshot]
#
# Creates <check directory>/backup-<UTC timestamp>/ with: MANIFEST.json; `defaults export` of the four domains the
# actions touch; keys.tsv (the five action keys, read with the defaults tool); the wallpaper store directory listing
# and a copy of Index.plist; world.json from the tool; sw_vers.txt. A desktop screenshot is taken only with
# --screenshot, because screencapture may ask for a privacy permission, which the protocol never requests.
# Prints the backup path on the last line.
set -euo pipefail
source "$(dirname "$0")/adapter-check-lib.sh"

screenshot=no
if [[ ${1:-} == --screenshot ]]; then screenshot=yes; fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$CHECK_DIR/backup-$stamp"
mkdir -p "$backup/defaults" "$backup/wallpaper"

for domain in com.apple.finder com.apple.dock com.apple.controlcenter NSGlobalDomain; do
    defaults export "$domain" "$backup/defaults/$domain.plist"
done
read_action_keys >"$backup/keys.tsv"
ls -lR "$WALLPAPER_DIR" >"$backup/wallpaper/listing.txt"
cp -p "$WALLPAPER_STORE" "$backup/wallpaper/Index.plist"
sw_vers >"$backup/sw_vers.txt"
"$ROOT/Scripts/adapter-check.sh" --result-file "$backup/world.json" world >/dev/null

screenshot_note="skipped: not requested (screencapture may ask for a privacy permission)"
if [[ $screenshot == yes ]]; then
    screencapture -x "$backup/desktop.png"
    screenshot_note="desktop.png"
fi

jq -n \
    --arg createdAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg macOS "$(sw_vers -productVersion)" \
    --arg screenshot "$screenshot_note" \
    '{formatVersion: 1, createdAt: $createdAt, macOSVersion: $macOS, screenshot: $screenshot,
      files: ["keys.tsv", "world.json", "wallpaper/Index.plist", "wallpaper/listing.txt", "sw_vers.txt",
              "defaults/com.apple.finder.plist", "defaults/com.apple.dock.plist",
              "defaults/com.apple.controlcenter.plist", "defaults/NSGlobalDomain.plist"]}' \
    >"$backup/MANIFEST.json"

echo "applications: $(jq '.details.applications | length' "$backup/world.json"), displays: $(jq '.details.displays | length' "$backup/world.json")"
echo "$backup"
