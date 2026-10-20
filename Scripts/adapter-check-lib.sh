#!/usr/bin/env bash
# Shared definitions for the adapter check scripts (docs/13-adapter-check.md). Sourced, never run.
#
# The five preference keys the actions change, the check directory, the built Debug app and the wallpaper store.
# Keys are read with the `defaults` tool only, so the scripts stay independent of the code under test.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="${PRESENTER_CHECK_DIR:-$HOME/presenter-check}"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Presenter.app"
WALLPAPER_DIR="$HOME/Library/Application Support/com.apple.wallpaper"
WALLPAPER_STORE="$WALLPAPER_DIR/Store/Index.plist"
ACTION_KEYS=(
    "com.apple.finder CreateDesktop"
    "com.apple.dock autohide"
    "com.apple.controlcenter AutoHideMenuBarOption"
    "NSGlobalDomain _HIHideMenuBar"
    "NSGlobalDomain AppleMenuBarVisibleInFullscreen"
)

# Prints "<domain>\t<key>\t<type>\t<value>" for one key, or "<domain>\t<key>\tabsent\t-" when it is absent.
# Booleans are printed as true or false, integers as decimal numbers, other types as `defaults read` prints them.
read_action_key() {
    local domain="$1" key="$2" type_line type value
    if ! type_line=$(defaults read-type "$domain" "$key" 2>/dev/null); then
        printf '%s\t%s\tabsent\t-\n' "$domain" "$key"
        return
    fi
    type="${type_line#Type is }"
    value=$(defaults read "$domain" "$key")
    if [[ $type == boolean ]]; then
        if [[ $value == 1 ]]; then value=true; else value=false; fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$domain" "$key" "$type" "$value"
}

# Prints the current values of all action keys in the format of read_action_key.
read_action_keys() {
    local entry
    for entry in "${ACTION_KEYS[@]}"; do
        # shellcheck disable=SC2086 # the entry is "<domain> <key>", split on purpose
        read_action_key $entry
    done
}
