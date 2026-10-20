#!/usr/bin/env bash
# Runs one command of the DEBUG-only adapter check tool inside the real app bundle (docs/13-adapter-check.md, ADR-042).
#
# Usage: Scripts/adapter-check.sh [--no-build] [--language <code>] [--result-file <path>] <command> [tool options]
#
# Builds the Debug app (unless --no-build), launches it through `open -n -W` so macOS attributes the process to the
# app bundle (the way the M0 spike S4 launched its bundles), prints the tool's JSON event lines and its JSON result,
# and exits nonzero when the result's status is not "ok". --language <code> launches the app with
# -AppleLanguages "(<code>)", for example to see the Russian Automation prompt.
# Output files stay under the check directory ($PRESENTER_CHECK_DIR or ~/presenter-check), never in the repository.
set -euo pipefail
source "$(dirname "$0")/adapter-check-lib.sh"

usage() {
    echo "usage: $0 [--no-build] [--language <code>] [--result-file <path>] <command> [tool options]" >&2
    exit 2
}

build=yes
language=""
result_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --no-build) build=no; shift ;;
    --language) [[ $# -ge 2 ]] || usage; language="$2"; shift 2 ;;
    --result-file) [[ $# -ge 2 ]] || usage; result_file="$2"; shift 2 ;;
    *) break ;;
    esac
done
[[ $# -ge 1 ]] || usage
command="$1"

if [[ $build == yes ]]; then
    (cd "$ROOT" && make build >/dev/null)
fi
[[ -d $APP ]] || { echo "error: $APP does not exist; run without --no-build" >&2; exit 1; }

mkdir -p "$CHECK_DIR/results"
if [[ ! -f "$CHECK_DIR/profiles.json" ]]; then
    sed "s|__CHECK_DIR__|$CHECK_DIR|g" "$ROOT/Scripts/adapter-check-profiles.json" >"$CHECK_DIR/profiles.json"
fi
base="$CHECK_DIR/results/$command-$(date -u +%Y%m%dT%H%M%SZ)"
[[ -n $result_file ]] || result_file="$base.result.json"
rm -f "$result_file"

arguments=(--adapter-check "$@" --result "$result_file" --check-dir "$CHECK_DIR")
if [[ -n $language ]]; then
    arguments+=(-AppleLanguages "($language)")
fi
open -n -W -a "$APP" --stdout "$base.stdout.jsonl" --stderr "$base.stderr.txt" --args "${arguments[@]}"

cat "$base.stdout.jsonl"
if [[ ! -f $result_file ]]; then
    echo "error: no result file; the tool did not finish (see $base.stderr.txt)" >&2
    exit 1
fi
cat "$result_file"
echo
[[ $(jq -r .status "$result_file") == ok ]]
