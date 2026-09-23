#!/bin/sh
# Print the Kristal engine root that contains this mod (a directory holding
# main.lua + src/kristal.lua, walking up from the mod root) — the same probe
# the debug launcher uses. Empty output / exit 1 when none is found.
set -eu
dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/main.lua" ] && [ -f "$dir/src/kristal.lua" ]; then
        printf '%s\n' "$dir"
        exit 0
    fi
    dir=$(dirname "$dir")
done
exit 1
