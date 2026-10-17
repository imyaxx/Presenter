#!/usr/bin/env bash
# Checks that the development tools passed as arguments are usable and prints the one-line fix
# for each one that is not. Called by the Makefile before any target that needs the tools.
#
# Usage: Scripts/require-tools.sh <tool>...
# Known tools: xcodegen, swiftlint, swift-format, xcodebuild.
# For xcodebuild it also checks that a full Xcode is selected and its license is accepted.
set -euo pipefail

report_missing() {
    echo "error: $1. Fix: $2" >&2
    status=1
}

check_xcode() {
    if ! xcodebuild -version >/dev/null 2>&1; then
        report_missing "full Xcode is not selected" \
            "install Xcode, then run: sudo xcode-select --switch /Applications/Xcode.app"
    elif ! xcodebuild -license check >/dev/null 2>&1; then
        report_missing "Xcode license is not accepted" "sudo xcodebuild -license accept"
    fi
}

check_homebrew_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        report_missing "$1 is not installed" "brew install $1"
    fi
}

status=0
for tool in "$@"; do
    case "$tool" in
        xcodebuild) check_xcode ;;
        xcodegen | swiftlint | swift-format) check_homebrew_tool "$tool" ;;
        *)
            echo "error: unknown tool '$tool'" >&2
            exit 2
            ;;
    esac
done
exit "$status"
