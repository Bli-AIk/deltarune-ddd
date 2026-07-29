"""Shared Blender art direction for the King Battle authored scene.

This module constructs presentation geometry only. Static scene placement,
including all pendant, cage, and camera transforms, remains in the editable
``kingbattle_layout.blend`` file.
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


SUITS = ("club", "spade", "heart", "diamond")
STYLE_VERSION = 3

EDGE_MATERIAL = "suit_edge"
FILL_MATERIAL = "suit_fill"

# Purple edge treatment is real scene geometry. It follows feature edges in
# the closed suit mesh, so a box would receive all twelve physical edges,
# including the edges on its rear and side faces.
FEATURE_EDGE_COSINE = math.cos(math.radians(32.0))
EDGE_RADIUS_FACTOR = 0.009
EDGE_MIN_RADIUS = 0.008
EDGE_SEGMENTS = 6

# Cage and chain use the same restrained CC0 PBR set. The runtime shader uses
# these maps too; keeping the Blender node graph here makes the authored
# layout a faithful source of truth for artists inspecting the scene.
METAL_TEXTURE_SET = "blue_metal_plate"
METAL_TEXTURE_FILES = {
    "albedo": "blue_metal_plate_diff_1k.jpg",
    "normal": "blue_metal_plate_nor_gl_1k.jpg",
    "roughness": "blue_metal_plate_rough_1k.jpg",
}
METAL_UV_SCALE = (1.0, 1.0, 1.0)
METAL_NORMAL_STRENGTH = 0.22

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


def _texture_path(filename: str) -> Path:
    if not bpy.data.filepath:
        raise RuntimeError("King Battle texture paths require a saved Blender layout.")
    path = Path(bpy.data.filepath).resolve().parent / "textures" / filename
    if not path.is_file():
        raise RuntimeError(f"Required King Battle texture is missing: {path}")
    return path


def _load_texture(filename: str, color_space: str) -> bpy.types.Image:
    path = _texture_path(filename)
    image = bpy.data.images.get(filename)
    if image is None:
        image = bpy.data.images.load(str(path), check_existing=True)
        image.name = filename
    image.filepath = bpy.path.relpath(str(path))
    try:
        image.colorspace_settings.name = color_space
    except TypeError as error:
        raise RuntimeError(
            f"Could not assign {color_space!r} color space to '{filename}': {error}"
        ) from error
    return image


def _configure_metal_texture_nodes(
    material: bpy.types.Material,
    specification: dict[str, object],
) -> None:
    """Create the idempotent Blender counterpart of the runtime PBR material."""

    tree = material.node_tree
    if tree is None:
        raise RuntimeError(f"'{material.name}' has no node tree.")
    nodes = tree.nodes
    links = tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.name = "DDD Metal Output"
    output.location = (720, 0)
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.name = "DDD Metal Principled"
    principled.location = (460, 0)
    principled.inputs["Metallic"].default_value = specification["metallic"]

    coordinate = nodes.new("ShaderNodeTexCoord")
    coordinate.name = "DDD Metal Coordinates"
    coordinate.location = (-920, 0)
    mapping = nodes.new("ShaderNodeMapping")
    mapping.name = "DDD Metal UV Scale"
    mapping.location = (-740, 0)
    mapping.inputs["Scale"].default_value = METAL_UV_SCALE
    links.new(coordinate.outputs["UV"], mapping.inputs["Vector"])

    albedo = nodes.new("ShaderNodeTexImage")
    albedo.name = "DDD Metal Albedo"
    albedo.label = "Blue Metal Plate Albedo"
    albedo.image = _load_texture(METAL_TEXTURE_FILES["albedo"], "sRGB")
    albedo.location = (-520, 170)
    links.new(mapping.outputs["Vector"], albedo.inputs["Vector"])

    tint = nodes.new("ShaderNodeRGB")
    tint.name = "DDD Metal Purple Tint"
    tint.label = "Scene Purple Tint"
    tint.location = (-520, 55)
    tint.outputs["Color"].default_value = specification["color"]
    color_mix = nodes.new("ShaderNodeMixRGB")
    color_mix.name = "DDD Metal Albedo Tint"
    color_mix.blend_type = "MULTIPLY"
    color_mix.inputs["Fac"].default_value = 0.42
    color_mix.location = (-110, 130)
    links.new(tint.outputs["Color"], color_mix.inputs[1])
    links.new(albedo.outputs["Color"], color_mix.inputs[2])
    links.new(color_mix.outputs["Color"], principled.inputs["Base Color"])

    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.name = "DDD Metal Normal Texture"
    normal_texture.label = "Blue Metal Plate Normal (OpenGL)"
    normal_texture.image = _load_texture(METAL_TEXTURE_FILES["normal"], "Non-Color")
    normal_texture.location = (-520, -120)
    links.new(mapping.outputs["Vector"], normal_texture.inputs["Vector"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.name = "DDD Metal Normal"
    normal_map.location = (-110, -120)
    normal_map.inputs["Strength"].default_value = METAL_NORMAL_STRENGTH
    links.new(normal_texture.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])

    roughness_texture = nodes.new("ShaderNodeTexImage")
    roughness_texture.name = "DDD Metal Roughness Texture"
    roughness_texture.label = "Blue Metal Plate Roughness"
    roughness_texture.image = _load_texture(METAL_TEXTURE_FILES["roughness"], "Non-Color")
    roughness_texture.location = (-520, -390)
    links.new(mapping.outputs["Vector"], roughness_texture.inputs["Vector"])
    roughness_range = nodes.new("ShaderNodeMapRange")
    roughness_range.name = "DDD Metal Roughness Range"
    roughness_range.location = (-110, -360)
    roughness_range.inputs["From Min"].default_value = 0.0
    roughness_range.inputs["From Max"].default_value = 1.0
    roughness_range.inputs["To Min"].default_value = 0.20
    roughness_range.inputs["To Max"].default_value = 0.52
    links.new(roughness_texture.outputs["Color"], roughness_range.inputs["Value"])
    links.new(roughness_range.outputs["Result"], principled.inputs["Roughness"])

    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    material["ddd_pbr_texture_set"] = METAL_TEXTURE_SET
    material["ddd_normal_strength"] = METAL_NORMAL_STRENGTH
    material["ddd_uv_scale"] = METAL_UV_SCALE[:2]


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
    if name in {"cage_metal", "chain_metal"}:
        _configure_metal_texture_nodes(material, specification)
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
