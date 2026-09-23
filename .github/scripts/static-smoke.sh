#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)

test -f "$root/mod.lua"
test -f "$root/scripts/world/maps/room_cc_kingbattle.lua"
test -f "$root/libraries/kristal-i18n/lib.lua"
test -f "$root/libraries/kristal-object-selector-plus/lib.lua"
test -f "$root/libraries/terminal-cli/lib.lua"
test -f "$root/libraries/kristal-debug-tools/lib.lua"
test -f "$root/libraries/virtualkeyboard/lib.lua"
test -f "$root/libraries/virtualkeyboard/lib.json"
grep -F '"engineVer": "v0.11.0-dev"' "$root/mod.json" >/dev/null
grep -F '"darkInventory": {' "$root/mod.json" >/dev/null
if grep -F '"inventory": {' "$root/mod.json" >/dev/null; then
    printf '%s\n' 'mod.json must use darkInventory on Kristal 0.11.0-dev' >&2
    exit 1
fi
luajit -b "$root/libraries/virtualkeyboard/lib.lua" /dev/null
