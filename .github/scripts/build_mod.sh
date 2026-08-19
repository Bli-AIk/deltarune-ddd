#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)"
DELTARUNE_DDD_CH1_BUILD_DIR="${DELTARUNE_DDD_CH1_MOD_BUILD_DIR:-$ROOT/.build/mod}"
DELTARUNE_DDD_CH1_OUTPUT_DIR="${DELTARUNE_DDD_CH1_OUTPUT_DIR:-$ROOT/dist}"
DELTARUNE_DDD_CH1_OUTPUT_FILE="${DELTARUNE_DDD_CH1_MOD_OUTPUT_FILE:-$DELTARUNE_DDD_CH1_OUTPUT_DIR/deltarune-ddd-ch1-mod.zip}"
STAGE_DIR="$DELTARUNE_DDD_CH1_BUILD_DIR/source"

command -v python3 >/dev/null
command -v rsync >/dev/null
command -v unzip >/dev/null
command -v zip >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
rsync -a \
    --exclude='/.git/' \
    --exclude='.git' \
    --exclude='/.github/' \
    --exclude='/.build/' \
    --exclude='/dist/' \
    --exclude='/.emacs/' \
    --exclude='/.helix/' \
    --exclude='/.vscode/' \
    --exclude='/.worktrees/' \
    --exclude='/tests/' \
    --exclude='/docs/' \
    --exclude='/Makefile' \
    --exclude='/justfile' \
    --exclude='/build_standalone.sh' \
    --exclude='/build_standalone.py' \
    --exclude='/build_android.sh' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    --exclude='/release-please-config.json' \
    --exclude='/.release-please-manifest.json' \
    --exclude='/.gitmodules' \
    --exclude='/.gitignore' \
    --exclude='*.tiled-project' \
    --exclude='*.tiled-session' \
    "$ROOT/" "$STAGE_DIR/"

rm -rf "$STAGE_DIR/libraries/kristal-object-selector-plus"
rm -rf "$STAGE_DIR/libraries/terminal-cli"
rm -rf "$STAGE_DIR/libraries/kristal-debug-tools"
python3 "$ROOT/build_standalone.py" patch-mod-manifest "$STAGE_DIR/mod.json" false false
rm -f "$DELTARUNE_DDD_CH1_OUTPUT_FILE"
(cd "$STAGE_DIR" && zip -9 -q -r "$DELTARUNE_DDD_CH1_OUTPUT_FILE" .)
test -s "$DELTARUNE_DDD_CH1_OUTPUT_FILE"
unzip -t "$DELTARUNE_DDD_CH1_OUTPUT_FILE" >/dev/null
unzip -Z1 "$DELTARUNE_DDD_CH1_OUTPUT_FILE" | grep -Fx 'mod.json' >/dev/null
printf 'Created Mod package: %s\n' "$DELTARUNE_DDD_CH1_OUTPUT_FILE"
