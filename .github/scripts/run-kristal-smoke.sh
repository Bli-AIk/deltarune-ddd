#!/bin/sh
set -eu

: "${KRISTAL:?set KRISTAL to a clean Kristal v0.10 checkout}"

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
mod_id=deltarune-ddd-ch1
mod_path="$KRISTAL/mods/$mod_id"
log=$(mktemp)
sandbox=$(mktemp -d)
created=0

cleanup() {
    rm -f "$log"
    rm -rf "$sandbox"
    if [ "$created" = 1 ]; then
        rm -rf "$mod_path"
    fi
}
trap cleanup EXIT HUP INT TERM

test -d "$KRISTAL"
test -d "$KRISTAL/mods"
test ! -e "$mod_path"
mkdir "$mod_path"
created=1
rsync -aL --exclude='.git' --exclude='.build' --exclude='dist' "$root/" "$mod_path/"

mkdir -p "$sandbox/home" "$sandbox/data" "$sandbox/config" "$sandbox/cache" "$sandbox/runtime"
chmod 700 "$sandbox/runtime"
timeout --kill-after=5s 45s xvfb-run -a env \
    HOME="$sandbox/home" \
    XDG_DATA_HOME="$sandbox/data" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_CACHE_HOME="$sandbox/cache" \
    XDG_RUNTIME_DIR="$sandbox/runtime" \
    SDL_AUDIODRIVER=dummy \
    ALSOFT_DRIVERS=null \
    LIBGL_ALWAYS_SOFTWARE=1 \
    KRISTAL_MOD_SMOKE=1 \
    love "$KRISTAL" --mod "$mod_id" --auto-mod-start >"$log" 2>&1 || {
        cat "$log" >&2
        exit 1
    }
grep -F 'KRISTAL_MOD_SMOKE=PASS' "$log"
