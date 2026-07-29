#!/usr/bin/env python3
"""Apply the King Battle visual style to an existing authored Blender layout.

Run after opening the layout, not the raw source model:

    blender --background assets/3d/kingbattle/kingbattle_layout.blend \
        --python tools/apply_kingbattle_layout_style.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


SCRIPT_PATH = Path(__file__).resolve()
if str(SCRIPT_PATH.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT_PATH.parent))

import kingbattle_layout_style as style


LAYOUT_COLLECTION = "DDD_KINGBATTLE"


def main() -> None:
    if not bpy.data.filepath:
        raise RuntimeError("Open kingbattle_layout.blend before applying its visual style.")
    collection = bpy.data.collections.get(LAYOUT_COLLECTION)
    if collection is None:
        raise RuntimeError(f"Missing Blender collection '{LAYOUT_COLLECTION}'.")
    result = style.apply_layout_style(collection)
    bpy.ops.wm.save_mainfile()
    print(
        "Applied King Battle layout style "
        f"v{result['style_version']} to {bpy.data.filepath}."
    )


if __name__ == "__main__":
    main()
