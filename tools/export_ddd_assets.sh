#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MOD_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BLENDER_BIN=${BLENDER_BIN:-blender}
ASSET_ROOT="$MOD_ROOT/assets/3d/kingbattle"

exec "$BLENDER_BIN" \
    --background "$ASSET_ROOT/kingbattle_layout.blend" \
    --python "$MOD_ROOT/tools/export_ddd_assets.py" \
    -- \
    --output "$ASSET_ROOT" \
    "$@"
