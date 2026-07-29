#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
fake_engine=$(mktemp -d)
touch "$fake_engine/main.lua"
cleanup() {
    rm -f "$fake_engine/main.lua"
    rmdir "$fake_engine"
}
trap cleanup EXIT HUP INT TERM
engine_root=${KRISTAL_ROOT:-$fake_engine}

run_dry() {
    KRISTAL_ROOT="$engine_root" \
    KRISTAL_DEBUG_TOOLS_DRY_RUN=1 \
    just --justfile "$root/justfile" run "$@"
}

output=$(run_dry --wave 2 --tp 50 --mercy 100)
printf '%s\n' "$output" | grep -Fqx "mod_root=$root"
printf '%s\n' "$output" | grep -Fqx 'mod_id=thrash-machine'
printf '%s\n' "$output" | grep -F -- '--wave 2' >/dev/null
printf '%s\n' "$output" | grep -F -- '--tp 50' >/dev/null
printf '%s\n' "$output" | grep -F -- '--mercy 100' >/dev/null

output=$(run_dry --encounter --initial-tp=25 --initial-mercy=75)
printf '%s\n' "$output" | grep -F -- '--encounter' >/dev/null
printf '%s\n' "$output" | grep -F -- '--tp 25' >/dev/null
printf '%s\n' "$output" | grep -F -- '--mercy 75' >/dev/null

output=$(run_dry --wave-force 3)
printf '%s\n' "$output" | grep -F -- '--wave-force 3' >/dev/null

output=$(run_dry -- --custom value)
printf '%s\n' "$output" | grep -F -- '--custom value' >/dev/null

if run_dry --tp >/dev/null 2>&1; then
    printf '%s\n' 'missing-value validation failed' >&2
    exit 1
fi

if run_dry --unknown >/dev/null 2>&1; then
    printf '%s\n' 'unknown-option validation failed' >&2
    exit 1
fi

printf '%s\n' 'template debug-tools smoke: PASS'
