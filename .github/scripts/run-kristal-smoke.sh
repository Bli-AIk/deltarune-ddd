#!/bin/sh
set -eu

: "${KRISTAL:?set KRISTAL to a clean Kristal 0.11.0-dev checkout}"

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
mod_id=deltarune-ddd-ch1
mod_path="$KRISTAL/mods/$mod_id"
log=$(mktemp)
sandbox=$(mktemp -d)
copied=0

cleanup() {
    rm -f "$log"
    rm -rf "$sandbox"
    if [ "$copied" = 1 ]; then
        rm -rf "$mod_path"
    fi
}
trap cleanup EXIT HUP INT TERM

test -d "$KRISTAL"
test -d "$KRISTAL/mods"

if [ -e "$mod_path" ]; then
    # The project already lives inside this engine checkout (the common dev layout
    # where the engine is the parent of the project). Smoke-test it in place; do
    # not copy over a live working tree.
    printf 'project %s already present in engine — testing in place\n' "$mod_id" >&2
else
    mkdir "$mod_path"
    copied=1
    # rsync is not shipped with Git for Windows; a tar pipe is portable.
    ( cd "$root" && tar --exclude=.git --exclude=.build --exclude='dist*' -cf - . ) |
        ( cd "$mod_path" && tar -xf - ) || exit 1
fi

mkdir -p "$sandbox/home" "$sandbox/data" "$sandbox/config" "$sandbox/cache" "$sandbox/runtime"
chmod 700 "$sandbox/runtime"
# xvfb-run is Linux-only; elsewhere love opens a real window (or runs headless
# in a non-interactive session) and the env-only launch works.
if command -v xvfb-run >/dev/null 2>&1; then
    launch='xvfb-run -a env'
else
    launch='env'
fi
# Prefer the console build where it exists (Windows): lovec writes stdout (the
# smoke log) directly, where love.exe is a GUI-subsystem binary.
if command -v lovec >/dev/null 2>&1; then
    love_cmd=lovec
else
    love_cmd=love
fi
# `timeout --kill-after` is a GNUism; plain timeout is portable.
timeout 45s $launch \
    HOME="$sandbox/home" \
    XDG_DATA_HOME="$sandbox/data" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_CACHE_HOME="$sandbox/cache" \
    XDG_RUNTIME_DIR="$sandbox/runtime" \
    SDL_AUDIODRIVER=dummy \
    ALSOFT_DRIVERS=null \
    LIBGL_ALWAYS_SOFTWARE=1 \
    KRISTAL_MOD_SMOKE=1 \
    $love_cmd "$KRISTAL" --mod "$mod_id" --auto-mod-start >"$log" 2>&1 || {
        cat "$log" >&2
        exit 1
    }
grep -F 'KRISTAL_MOD_SMOKE=PASS' "$log"
