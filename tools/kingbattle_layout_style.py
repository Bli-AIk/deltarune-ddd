"""Shared Blender art direction for the King Battle authored scene.

This module constructs presentation geometry only. Static scene placement,
including all pendant, cage, and camera transforms, remains in the editable
``kingbattle_layout.blend`` file.
"""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector


SUITS = ("club", "spade", "heart", "diamond")
STYLE_VERSION = 2

EDGE_MATERIAL = "suit_edge"
FILL_MATERIAL = "suit_fill"

# Purple edge treatment is real scene geometry. It follows feature edges in
# the closed suit mesh, so a box would receive all twelve physical edges,
# including the edges on its rear and side faces.
FEATURE_EDGE_COSINE = math.cos(math.radians(32.0))
EDGE_RADIUS_FACTOR = 0.009
EDGE_MIN_RADIUS = 0.008
EDGE_SEGMENTS = 6

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
    EDGE_MATERIAL: {
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


def _remove_object(object_: bpy.types.Object) -> None:
    mesh = object_.data if object_.type == "MESH" else None
    bpy.data.objects.remove(object_, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _find_fill_mesh(suit: bpy.types.Object, suit_name: str) -> bpy.types.Object:
    candidates = (
        f"{suit_name}_fill_mesh_00",
        f"{suit_name}_outline_mesh_00",
        f"{suit_name}_mesh_00",
    )
    for name in candidates:
        object_ = bpy.data.objects.get(name)
        if object_ is None:
            continue
        if object_.parent != suit:
            raise RuntimeError(f"'{name}' must be a direct child of '{suit_name}'.")
        if object_.type != "MESH":
            raise RuntimeError(f"'{name}' must be a mesh.")

        # Version 1 created a scaled fill duplicate under the original purple
        # outline mesh. Version 2 keeps the original as the black solid body.
        old_outline = bpy.data.objects.get(f"{suit_name}_outline_mesh_00")
        old_fill = bpy.data.objects.get(f"{suit_name}_fill_mesh_00")
        if old_outline is not None and object_ == old_fill:
            object_ = old_outline
        if old_fill is not None and old_fill != object_:
            _remove_object(old_fill)
        object_.name = f"{suit_name}_fill_mesh_00"
        return object_
    raise RuntimeError(f"'{suit_name}' needs one source mesh for its solid fill.")


def _feature_edge_segments(mesh: bpy.types.Mesh) -> list[tuple[Vector, Vector]]:
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bm.normal_update()
        segments = []
        for edge in bm.edges:
            linked_faces = edge.link_faces
            is_boundary = len(linked_faces) != 2
            is_crease = (
                not is_boundary
                and linked_faces[0].normal.dot(linked_faces[1].normal)
                < FEATURE_EDGE_COSINE
            )
            if is_boundary or is_crease:
                segments.append((edge.verts[0].co.copy(), edge.verts[1].co.copy()))
        return segments
    finally:
        bm.free()


def _edge_radius(mesh: bpy.types.Mesh) -> float:
    coordinates = [vertex.co for vertex in mesh.vertices]
    if not coordinates:
        raise RuntimeError(f"'{mesh.name}' has no vertices.")
    size = Vector((
        max(point.x for point in coordinates) - min(point.x for point in coordinates),
        max(point.y for point in coordinates) - min(point.y for point in coordinates),
        max(point.z for point in coordinates) - min(point.z for point in coordinates),
    ))
    return max(EDGE_MIN_RADIUS, max(size) * EDGE_RADIUS_FACTOR)


def _append_tube(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, int, int]],
    start: Vector,
    finish: Vector,
    radius: float,
) -> None:
    direction = finish - start
    if direction.length < 0.0001:
        return
    axis = direction.normalized()
    reference = Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(reference)) > 0.92:
        reference = Vector((0.0, 1.0, 0.0))
    tangent = axis.cross(reference).normalized()
    bitangent = axis.cross(tangent).normalized()
    first = len(vertices)
    for point in (start, finish):
        for segment in range(EDGE_SEGMENTS):
            angle = math.tau * segment / EDGE_SEGMENTS
            offset = tangent * math.cos(angle) * radius + bitangent * math.sin(angle) * radius
            vertices.append(tuple(point + offset))
    for segment in range(EDGE_SEGMENTS):
        next_segment = (segment + 1) % EDGE_SEGMENTS
        start_a = first + segment
        start_b = first + next_segment
        finish_a = first + EDGE_SEGMENTS + segment
        finish_b = first + EDGE_SEGMENTS + next_segment
        faces.append((start_a, start_b, finish_b))
        faces.append((start_a, finish_b, finish_a))


def _rebuild_edge_mesh(
    collection: bpy.types.Collection,
    suit: bpy.types.Object,
    suit_name: str,
    fill: bpy.types.Object,
) -> bpy.types.Object:
    name = f"{suit_name}_edge_mesh_00"
    previous = bpy.data.objects.get(name)
    if previous is not None:
        _remove_object(previous)

    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    radius = _edge_radius(fill.data)
    segments = _feature_edge_segments(fill.data)
    for start, finish in segments:
        _append_tube(vertices, faces, start, finish, radius)
    if not faces:
        raise RuntimeError(f"'{suit_name}' has no usable feature edges.")

    mesh = bpy.data.meshes.new(f"{suit_name}_edge_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(ensure_material(EDGE_MATERIAL))
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True

    edge = bpy.data.objects.new(name, mesh)
    collection.objects.link(edge)
    edge.parent = suit
    edge.matrix_parent_inverse.identity()
    edge.location = fill.location.copy()
    edge.rotation_mode = fill.rotation_mode
    edge.rotation_euler = fill.rotation_euler.copy()
    edge.scale = fill.scale.copy()
    edge["ddd_role"] = "suit_edge"
    edge["ddd_feature_edge_count"] = len(segments)
    return edge


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
    fill = _find_fill_mesh(suit, suit_name)
    fill["ddd_role"] = "suit_fill"
    _assign_material(fill, ensure_material(FILL_MATERIAL))
    _rebuild_edge_mesh(collection, suit, suit_name, fill)
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
