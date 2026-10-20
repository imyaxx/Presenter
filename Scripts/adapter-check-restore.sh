#!/usr/bin/env bash
# Emergency restore from an adapter check backup, independent of the code under test (docs/13-adapter-check.md).
# Use it only when `Scripts/adapter-check.sh recover` cannot restore.
#
# Usage: Scripts/adapter-check-restore.sh <backup directory>
#
# Writes each action key of keys.tsv back with the defaults tool (or deletes it when it was absent), restarts Finder
# when CreateDesktop changed and the Dock when autohide changed (the M0-verified mechanisms S5 and S4 B), copies
# Index.plist back and restarts WallpaperAgent, then posts the menu bar notification through the tool. Prints what it
# did and what it could not do.
set -euo pipefail
source "$(dirname "$0")/adapter-check-lib.sh"

[[ $# -eq 1 && -f "$1/keys.tsv" ]] || { echo "usage: $0 <backup directory with keys.tsv>" >&2; exit 2; }
backup="$1"
changed_domains=()

while IFS=$'\t' read -r domain key type value; do
    current=$(read_action_key "$domain" "$key")
    if [[ $current == "$domain"$'\t'"$key"$'\t'"$type"$'\t'"$value" ]]; then
        echo "unchanged: $domain $key"
        continue
    fi
    case "$type" in
    absent) defaults delete "$domain" "$key" ;;
    boolean) defaults write "$domain" "$key" -bool "$value" ;;
    integer) defaults write "$domain" "$key" -int "$value" ;;
    *) echo "could not restore $domain $key: type $type is not handled; restore it from defaults/$domain.plist"; continue ;;
    esac
    echo "restored: $domain $key -> $type $value"
    changed_domains+=("$domain")
done <"$backup/keys.tsv"

for domain in "${changed_domains[@]+"${changed_domains[@]}"}"; do
    case "$domain" in
    com.apple.finder) killall Finder && echo "restarted Finder" || echo "killall Finder exited $?" ;;
    com.apple.dock) killall Dock && echo "restarted Dock" || echo "killall Dock exited $?" ;;
    esac
done

cp "$backup/wallpaper/Index.plist" "$WALLPAPER_STORE"
echo "copied Index.plist back"
killall WallpaperAgent && echo "restarted WallpaperAgent" || echo "killall WallpaperAgent exited $?"

if "$ROOT/Scripts/adapter-check.sh" notify-menubar --backup "$backup" >/dev/null; then
    echo "posted the menu bar notification"
else
    echo "could not post the menu bar notification; log out and in to apply the menu bar keys"
fi
echo "check by eye: desktop icons, Dock auto-hide, menu bar and wallpaper; then run Scripts/adapter-check-diff.sh $backup"
