"""Shared Blender art direction for the King Battle authored scene.

This module constructs presentation geometry only. Static scene placement,
including all pendant, cage, and camera transforms, remains in the editable
``kingbattle_layout.blend`` file.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Vector


SUITS = ("club", "spade", "heart", "diamond")
STYLE_VERSION = 1

OUTLINE_MATERIAL = "suit_outline"
FILL_MATERIAL = "suit_fill"

# The fill is a separately authored mesh so it exports correctly through GLB
# and does not depend on a screen-space outline shader.
FILL_SCALE = Vector((0.78, 0.70, 0.78))
FILL_FRONT_OFFSET = -0.16

MATERIALS = {
    "cage_metal": {
        "color": (0.15, 0.14, 0.34, 1.0),
        "metallic": 0.62,
        "roughness": 0.28,
    },
    "chain_metal": {
        "color": (0.30, 0.25, 0.56, 1.0),
        "metallic": 0.72,
        "roughness": 0.20,
    },
    OUTLINE_MATERIAL: {
        "color": (0.43, 0.05, 0.94, 1.0),
        "metallic": 0.38,
        "roughness": 0.24,
    },
    FILL_MATERIAL: {
        "color": (0.008, 0.004, 0.020, 1.0),
        "metallic": 0.16,
        "roughness": 0.42,
    },
}


def _require_object(name: str) -> bpy.types.Object:
    object_ = bpy.data.objects.get(name)
    if object_ is None:
        raise RuntimeError(f"King Battle layout is missing required object '{name}'.")
    return object_


def ensure_material(name: str) -> bpy.types.Material:
    specification = MATERIALS[name]
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    material.diffuse_color = specification["color"]
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = specification["color"]
        principled.inputs["Metallic"].default_value = specification["metallic"]
        principled.inputs["Roughness"].default_value = specification["roughness"]
    return material


def _assign_material(object_: bpy.types.Object, material: bpy.types.Material) -> None:
    if object_.type != "MESH":
        raise RuntimeError(f"'{object_.name}' must be a mesh to receive a material.")
    object_.data.materials.clear()
    object_.data.materials.append(material)


def _find_outline_mesh(suit: bpy.types.Object, suit_name: str) -> bpy.types.Object:
    candidates = (
        f"{suit_name}_outline_mesh_00",
        f"{suit_name}_mesh_00",
    )
    for name in candidates:
        object_ = bpy.data.objects.get(name)
        if object_ is not None:
            if object_.parent != suit:
                raise RuntimeError(f"'{name}' must be a direct child of '{suit_name}'.")
            if object_.type != "MESH":
                raise RuntimeError(f"'{name}' must be a mesh.")
            object_.name = f"{suit_name}_outline_mesh_00"
            return object_
    raise RuntimeError(f"'{suit_name}' needs one source mesh for its outline.")


def _ensure_fill_mesh(
    collection: bpy.types.Collection,
    suit: bpy.types.Object,
    suit_name: str,
    outline: bpy.types.Object,
) -> bpy.types.Object:
    name = f"{suit_name}_fill_mesh_00"
    fill = bpy.data.objects.get(name)
    if fill is None:
        fill = outline.copy()
        fill.data = outline.data.copy()
        fill.name = name
        collection.objects.link(fill)
    if fill.parent not in (None, suit):
        raise RuntimeError(f"'{name}' must be parented to '{suit_name}'.")
    fill.parent = suit
    fill.matrix_parent_inverse.identity()
    fill.location = outline.location + Vector((0.0, FILL_FRONT_OFFSET, 0.0))
    fill.rotation_mode = outline.rotation_mode
    fill.rotation_euler = outline.rotation_euler.copy()
    fill.scale = Vector((
        outline.scale.x * FILL_SCALE.x,
        outline.scale.y * FILL_SCALE.y,
        outline.scale.z * FILL_SCALE.z,
    ))
    fill["ddd_role"] = "suit_fill"
    return fill


def _apply_vertical_flip(suit: bpy.types.Object) -> None:
    if suit.get("ddd_vertical_flip"):
        return
    suit.rotation_mode = "XYZ"
    # In this layout's Blender-to-glTF basis, local Blender Y is the
    # face-normal axis, so a half turn flips the symbol in the game view.
    suit.rotation_euler.y += math.pi
    suit["ddd_vertical_flip"] = True


def style_suit(collection: bpy.types.Collection, suit_name: str) -> None:
    suit = _require_object(suit_name)
    outline = _find_outline_mesh(suit, suit_name)
    outline["ddd_role"] = "suit_outline"
    _assign_material(outline, ensure_material(OUTLINE_MATERIAL))

    fill = _ensure_fill_mesh(collection, suit, suit_name, outline)
    _assign_material(fill, ensure_material(FILL_MATERIAL))
    _apply_vertical_flip(suit)


def apply_layout_style(collection: bpy.types.Collection) -> dict[str, object]:
    """Apply the idempotent material and suit-treatment schema to a layout."""

    if collection is None:
        raise RuntimeError("King Battle layout collection is unavailable.")
    for material_name in MATERIALS:
        ensure_material(material_name)

    cage_material = ensure_material("cage_metal")
    chain_material = ensure_material("chain_metal")
    for object_ in collection.all_objects:
        if object_.type != "MESH":
            continue
        if object_.name.startswith("cage_mesh_"):
            _assign_material(object_, cage_material)
        elif object_.name.startswith("chain_") and "_mesh_" in object_.name:
            _assign_material(object_, chain_material)

    for suit_name in SUITS:
        style_suit(collection, suit_name)

    collection["ddd_style_version"] = STYLE_VERSION
    return {
        "style_version": STYLE_VERSION,
        "suits": list(SUITS),
        "materials": list(MATERIALS),
    }
