#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)

found=$(find "$root" \
    -path "$root/.git" -prune -o \
    -path "$root/.emacs" -prune -o \
    -path "$root/.helix" -prune -o \
    -path "$root/libraries" -prune -o \
    -path "$root/.build" -prune -o \
    -path "$root/dist" -prune -o \
    -type f \( -name '*.fnl' -o -name '*.fnlm' \) -print)
test -z "$found" || {
    printf 'Fennel source remains:\n%s\n' "$found" >&2
    exit 1
}

test -f "$root/mod.lua"
test -f "$root/scripts/world/maps/room1.lua"
test -f "$root/libraries/kristal-i18n/lib.lua"
test -f "$root/libraries/object-editor/lib.lua"
test -f "$root/libraries/terminal-cli/lib.lua"
test -f "$root/libraries/kristal-debug-tools/lib.lua"
test -f "$root/libraries/virtualkeyboard/lib.lua"
test -f "$root/libraries/virtualkeyboard/lib.json"
luajit -b "$root/libraries/virtualkeyboard/lib.lua" /dev/null
test ! -e "$root/libraries/fumos"
test ! -e "$root/flsproject.fnl"
if git -C "$root" config -f .gitmodules --get submodule.libraries/fumos.url >/dev/null 2>&1; then
    printf 'FUMOS remains in .gitmodules\n' >&2
    exit 1
fi
