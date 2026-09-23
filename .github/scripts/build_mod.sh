#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"
DELTARUNE_DDD_CH1_MOD_DIR="$ROOT"
DELTARUNE_DDD_CH1_BUILD_DIR="${DELTARUNE_DDD_CH1_MOD_BUILD_DIR:-$ROOT/.build/mod}"
DELTARUNE_DDD_CH1_OUTPUT_DIR="${DELTARUNE_DDD_CH1_OUTPUT_DIR:-$ROOT/dist}"
DELTARUNE_DDD_CH1_OUTPUT_FILE="${DELTARUNE_DDD_CH1_MOD_OUTPUT_FILE:-$DELTARUNE_DDD_CH1_OUTPUT_DIR/deltarune-ddd-ch1-mod.zip}"
# Same icon conventions as build_standalone.sh (defaults, but honour overrides).
DELTARUNE_DDD_CH1_ICON_DIR="${DELTARUNE_DDD_CH1_ICON_DIR:-$ROOT/assets/icon}"
DELTARUNE_DDD_CH1_WINDOW_ICON="${DELTARUNE_DDD_CH1_WINDOW_ICON:-$DELTARUNE_DDD_CH1_ICON_DIR/window_icon.png}"
STAGE_DIR="$DELTARUNE_DDD_CH1_BUILD_DIR/source"

# `zip` is optional: when missing, the build-helper (LÖVE) writes the zip.

# shellcheck source=build-helper/lib.sh
source "$ROOT/build-helper/lib.sh"
command -v unzip >/dev/null 2>&1 || fail 'Missing required command: unzip'

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
# Stage with tar instead of rsync (rsync is not available in Git Bash on
# Windows; tar is). Member names are "./…": a leading "./" pins a pattern to
# the project root, slash-free patterns match basenames anywhere.
tar -cf - \
    --exclude='*.git' \
    --exclude='./.github' \
    --exclude='./libraries/*/.github' \
    --exclude='./.claude' \
    --exclude='./libraries/*/.claude' \
    --exclude='./.build' \
    --exclude='./dist*' \
    --exclude='./.tools' \
    --exclude='./.emacs' \
    --exclude='./.helix' \
    --exclude='./.vscode' \
    --exclude='./.worktrees' \
    --exclude='./tests' \
    --exclude='./docs' \
    --exclude='./Makefile' \
    --exclude='./justfile' \
    --exclude='./gui.cmd' \
    --exclude='./tools' \
    --exclude='./build-helper' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    --exclude='./release-please-config.json' \
    --exclude='./.release-please-manifest.json' \
    --exclude='./.gitmodules' \
    --exclude='./.gitignore' \
    --exclude='*.tiled-project' \
    --exclude='*.tiled-session' \
    --exclude='./libraries/kristal-debug-tools/gui' \
    --exclude='./libraries/kristal-debug-tools-gui' \
    --exclude='./libraries/kristal-debug-tools/just.cmd' \
    --exclude='./libraries/kristal-debug-tools/dist' \
    --exclude='./libraries/kristal-debug-tools/.tools' \
    --exclude='./assets/icon' \
    -C "$ROOT" . | tar -xf - -C "$STAGE_DIR"

# The helper applies the complete release policy from library IDs: development
# tooling, optional-content selections, and required-dependency closure.
prune_release_optional_libraries "$STAGE_DIR"
run_helper patch-mod-manifest "$STAGE_DIR/mod.json" false false
if [ -f "$DELTARUNE_DDD_CH1_WINDOW_ICON" ]; then
    cp "$DELTARUNE_DDD_CH1_WINDOW_ICON" "$STAGE_DIR/window_icon.png"
    run_helper set-mod-json-flag "$STAGE_DIR/mod.json" setWindowTitleAndIcon true
fi
zip_dir "$DELTARUNE_DDD_CH1_OUTPUT_FILE" "$STAGE_DIR" ""
test -s "$DELTARUNE_DDD_CH1_OUTPUT_FILE"
unzip -t "$DELTARUNE_DDD_CH1_OUTPUT_FILE" >/dev/null
unzip -Z1 "$DELTARUNE_DDD_CH1_OUTPUT_FILE" | grep -Fx 'mod.json' >/dev/null
printf 'Created project package: %s\n' "$DELTARUNE_DDD_CH1_OUTPUT_FILE"
open_output_dir "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
