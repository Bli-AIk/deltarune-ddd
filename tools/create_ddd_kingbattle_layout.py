#!/usr/bin/env python3
"""Create the editable Blender-first King Battle layout source.

Run this once against the supplied model source:

    blender --background /home/aik/Documents/Blender/ddd-8.blend \
        --python tools/create_ddd_kingbattle_layout.py -- \
        --output assets/3d/kingbattle/kingbattle_layout.blend

The generated blend is the authority for every static transform in the
background. Open ``kingbattle_layout.blend`` in Blender to arrange the cage,
pendants, anchors, rotations, and scale. The game never reads these defaults;
it only consumes the GLB exported from the authored collection.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT_PATH = Path(__file__).resolve()
if str(SCRIPT_PATH.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT_PATH.parent))

import export_ddd_assets as source


DEFAULT_OUTPUT = (
    SCRIPT_PATH.parent.parent / "assets" / "3d" / "kingbattle" / "kingbattle_layout.blend"
)
LAYOUT_COLLECTION = "DDD_KINGBATTLE"
ROOT_NAME = "DDD_SCENE_ROOT"

# These values seed the first editable Blender file only. They are not used by
# the exporter or runtime after the layout blend has been created.
INITIAL_CAGE = {
    "position": (0.0, -4.0, -8.0),
    "scale": (1.14, 0.98, 1.06),
}

INITIAL_PENDANTS = {
    "club": {
        "position": (-8.70, -8.10, 0.25),
        "suit_rotation_z": 0.16,
        "suit_scale": (1.60, 1.60, 1.60),
        "chain_position": (0.0, -2.10, -0.15),
        "chain_scale": (1.16, 1.0, 1.0),
    },
    "spade": {
        "position": (-2.95, -7.70, 0.05),
        "suit_rotation_z": -0.12,
        "suit_scale": (1.67, 1.67, 1.67),
        "chain_position": (0.0, -2.10, -0.20),
        "chain_scale": (1.10, 1.0, 1.0),
    },
    "heart": {
        "position": (3.55, -8.00, 0.10),
        "suit_rotation_z": 0.14,
        "suit_scale": (1.72, 1.72, 1.72),
        "chain_position": (0.0, -2.10, -0.15),
        "chain_scale": (1.13, 1.0, 1.0),
    },
    "diamond": {
        "position": (8.95, -8.40, 0.25),
        "suit_rotation_z": -0.10,
        "suit_scale": (1.58, 1.58, 1.58),
        "chain_position": (0.0, -2.10, -0.05),
        "chain_scale": (1.07, 1.0, 1.0),
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create the editable Blender layout for the King Battle 3D background."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Destination .blend file (default: {DEFAULT_OUTPUT})",
    )
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def make_empty(collection: bpy.types.Collection, name: str, role: str) -> bpy.types.Object:
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty["ddd_role"] = role
    collection.objects.link(empty)
    return empty


def set_parent(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    child.parent = parent
    child.matrix_parent_inverse.identity()


def gltf_to_blender_position(position: tuple[float, float, float]) -> Vector:
    # Blender export_yup maps Blender (X, Y, Z) to glTF (X, Z, -Y).
    return Vector((position[0], -position[2], position[1]))


def set_gltf_transform(
    object_: bpy.types.Object,
    *,
    position: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rotation_z: float = 0.0,
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> None:
    """Set a local transform expressed in the GLB coordinate convention.

    All starter rotations are around glTF Z. Under the Blender-to-glTF basis
    conversion that is a negative Blender Y rotation. Future authoring is done
    in Blender directly, so this conversion is only needed for initial setup.
    """

    object_.location = gltf_to_blender_position(position)
    object_.rotation_mode = "XYZ"
    object_.rotation_euler = (0.0, -rotation_z, 0.0)
    object_.scale = (scale[0], scale[2], scale[1])


def attach_meshes(
    parent: bpy.types.Object,
    prepared: source.PreparedAsset,
    name_prefix: str,
) -> None:
    for index, object_ in enumerate(prepared.objects):
        object_.name = f"{name_prefix}_mesh_{index:02d}"
        set_parent(object_, parent)
        object_.location = (0.0, 0.0, 0.0)
        object_.rotation_euler = (0.0, 0.0, 0.0)
        object_.scale = (1.0, 1.0, 1.0)
        object_["ddd_role"] = "geometry"


def build_layout(collection: bpy.types.Collection) -> bpy.types.Object:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    root = make_empty(collection, ROOT_NAME, "scene_root")

    cage = make_empty(collection, "cage", "cage")
    set_parent(cage, root)
    set_gltf_transform(cage, **INITIAL_CAGE)
    cage_asset = source.prepare_asset(source.CAGE, depsgraph, collection)
    attach_meshes(cage, cage_asset, "cage")

    source_by_suit = {spec.asset_id: spec for spec in source.SUIT_SPECS}
    for suit_name, settings in INITIAL_PENDANTS.items():
        pendant = make_empty(collection, f"pendant_{suit_name}", "pendant")
        set_parent(pendant, root)
        set_gltf_transform(pendant, position=settings["position"])

        chain = make_empty(collection, f"chain_{suit_name}", "chain")
        set_parent(chain, pendant)
        set_gltf_transform(
            chain,
            position=settings["chain_position"],
            rotation_z=math.pi / 2,
            scale=settings["chain_scale"],
        )
        chain_asset = source.prepare_asset(source.CHAIN, depsgraph, collection)
        attach_meshes(chain, chain_asset, f"chain_{suit_name}")

        suit = make_empty(collection, suit_name, "suit")
        set_parent(suit, pendant)
        set_gltf_transform(
            suit,
            rotation_z=settings["suit_rotation_z"],
            scale=settings["suit_scale"],
        )
        suit_asset = source.prepare_asset(source_by_suit[suit_name], depsgraph, collection)
        attach_meshes(suit, suit_asset, suit_name)

    camera_anchor = make_empty(collection, "anchor_camera", "camera")
    set_parent(camera_anchor, root)
    set_gltf_transform(camera_anchor, position=(0.0, 1.35, 30.5))

    target_anchor = make_empty(collection, "anchor_camera_target", "camera_target")
    set_parent(target_anchor, root)
    set_gltf_transform(target_anchor, position=(0.0, 1.20, -3.0))

    fountain_anchor = make_empty(collection, "anchor_fountain", "fountain")
    set_parent(fountain_anchor, root)
    set_gltf_transform(fountain_anchor, position=(0.0, -2.0, -4.0))

    return root


def main() -> None:
    args = parse_args()
    destination = args.output.resolve()
    if not bpy.data.filepath:
        raise RuntimeError("Open ddd-8.blend before running this layout generator.")
    if bpy.data.collections.get(LAYOUT_COLLECTION) is not None:
        raise RuntimeError(
            f"'{LAYOUT_COLLECTION}' already exists. Edit and export that layout instead of bootstrapping it again."
        )

    destination.parent.mkdir(parents=True, exist_ok=True)
    collection = bpy.data.collections.new(LAYOUT_COLLECTION)
    bpy.context.scene.collection.children.link(collection)
    root = build_layout(collection)
    bpy.context.view_layer.objects.active = root
    root.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(destination), check_existing=False)
    print(f"Created editable King Battle layout: {destination}")
    print(f"Edit collection '{LAYOUT_COLLECTION}', then run tools/export_ddd_assets.py from that .blend.")


if __name__ == "__main__":
    main()
