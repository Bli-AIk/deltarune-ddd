#!/usr/bin/env python3
"""Export the Blender-authored King Battle scene to a loader-friendly GLB.

Run from the mod root after arranging ``kingbattle_layout.blend`` in Blender:

    blender --background assets/3d/kingbattle/kingbattle_layout.blend \
        --python tools/export_ddd_assets.py -- --output assets/3d/kingbattle

The ``DDD_KINGBATTLE`` collection is the single authority for cage, chain,
card-suit, anchor, and parent-child transforms. This exporter deliberately
does not position, rotate, or scale those objects. It only validates and emits
the authored hierarchy as one glTF 2.0 binary file.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import bmesh
import bpy
from mathutils import Matrix, Vector


SCRIPT_PATH = Path(__file__).resolve()
DEFAULT_OUTPUT = SCRIPT_PATH.parent.parent / "assets" / "3d" / "kingbattle"
LAYOUT_COLLECTION = "DDD_KINGBATTLE"
SCENE_FILE = "kingbattle_scene.glb"
SCENE_ROOT = "DDD_SCENE_ROOT"

SUITS = ("club", "spade", "heart", "diamond")
REQUIRED_NODES = (
    SCENE_ROOT,
    "cage",
    "anchor_camera",
    "anchor_camera_target",
    "anchor_fountain",
    *(f"pendant_{suit}" for suit in SUITS),
    *(f"chain_{suit}" for suit in SUITS),
    *SUITS,
)
REQUIRED_MATERIALS = {
    "cage_metal",
    "chain_metal",
    "suit_outline",
    "suit_fill",
}
SUIT_ORIENTATION = Matrix.Rotation(math.radians(90.0), 4, "X")


@dataclass(frozen=True)
class AssetSpec:
    asset_id: str
    material_name: str
    color: tuple[float, float, float, float]
    source_objects: tuple[str, ...]
    source_kind: str = "objects"
    is_suit: bool = False


@dataclass
class PreparedAsset:
    spec: AssetSpec
    source_center: Vector
    objects: list[bpy.types.Object]
    local_minimum: Vector
    local_maximum: Vector
    node_offset: Vector


CAGE = AssetSpec(
    asset_id="cage",
    material_name="cage_metal",
    color=(0.23, 0.31, 0.38, 1.0),
    source_objects=("hori", "vert"),
)
CHAIN = AssetSpec(
    asset_id="chain",
    material_name="chain_metal",
    color=(0.35, 0.39, 0.43, 1.0),
    source_objects=("chain.001", "chain"),
    source_kind="face_instances",
)
SUIT_SPECS = (
    AssetSpec(
        asset_id="club",
        material_name="suit_outline",
        color=(0.43, 0.05, 0.94, 1.0),
        source_objects=("Curve",),
        is_suit=True,
    ),
    AssetSpec(
        asset_id="spade",
        material_name="suit_outline",
        color=(0.43, 0.05, 0.94, 1.0),
        source_objects=("Curve.001",),
        is_suit=True,
    ),
    AssetSpec(
        asset_id="heart",
        material_name="suit_outline",
        color=(0.43, 0.05, 0.94, 1.0),
        source_objects=("Curve.002",),
        is_suit=True,
    ),
    AssetSpec(
        asset_id="diamond",
        material_name="suit_outline",
        color=(0.43, 0.05, 0.94, 1.0),
        source_objects=("Curve.003",),
        is_suit=True,
    ),
)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export the authored DDD King Battle layout as one GLB scene."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Destination directory (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--collection",
        default=LAYOUT_COLLECTION,
        help=f"Authored Blender collection to export (default: {LAYOUT_COLLECTION})",
    )
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def require_source_object(name: str) -> bpy.types.Object:
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(
            f"Expected source object '{name}' was not found in {bpy.data.filepath}."
        )
    return obj


def prepare_material(spec: AssetSpec) -> bpy.types.Material:
    material = bpy.data.materials.get(spec.material_name)
    if material is None:
        material = bpy.data.materials.new(spec.material_name)

    material.diffuse_color = spec.color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = spec.color
        principled.inputs["Metallic"].default_value = 0.86
        principled.inputs["Roughness"].default_value = 0.32
    return material


def triangulate(mesh: bpy.types.Mesh) -> None:
    """Keep all primitive modes explicitly triangular for the Lua loader."""
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
    finally:
        bm.free()
    mesh.update()


def evaluated_mesh(
    source: bpy.types.Object,
    depsgraph: bpy.types.Depsgraph,
    transform: Matrix,
    mesh_name: str,
) -> bpy.types.Mesh:
    """Create a standalone evaluated mesh with a world-space transform baked in."""
    source_eval = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(source_eval, depsgraph=depsgraph)
    if mesh is None or not mesh.vertices:
        raise RuntimeError(f"'{source.name}' did not evaluate to a non-empty mesh.")
    mesh.name = mesh_name
    mesh.transform(transform)
    triangulate(mesh)
    return mesh


def world_meshes_for_objects(
    source_names: Iterable[str], depsgraph: bpy.types.Depsgraph, asset_id: str
) -> list[tuple[str, bpy.types.Mesh]]:
    meshes = []
    for source_name in source_names:
        source = require_source_object(source_name)
        meshes.append(
            (
                source_name,
                evaluated_mesh(
                    source,
                    depsgraph,
                    source.matrix_world.copy(),
                    f"{asset_id}_{source_name}",
                ),
            )
        )
    return meshes


def world_meshes_for_face_instances(
    spec: AssetSpec, depsgraph: bpy.types.Depsgraph
) -> list[tuple[str, bpy.types.Mesh]]:
    """Bake the link object instanced across the evaluated face-array emitter."""
    emitter_name, link_name = spec.source_objects
    emitter = require_source_object(emitter_name)
    link = require_source_object(link_name)
    meshes = []

    # DepsgraphObjectInstance values are transient. Build each mesh inside the
    # iterator instead of retaining an instance reference after the next step.
    for index, instance in enumerate(depsgraph.object_instances):
        if not instance.is_instance or instance.object.original != link:
            continue
        parent = instance.parent.original if instance.parent else None
        if parent != emitter:
            continue
        meshes.append(
            (
                f"link_{len(meshes):02d}",
                evaluated_mesh(
                    instance.object,
                    depsgraph,
                    instance.matrix_world.copy(),
                    f"{spec.asset_id}_link_{index:02d}",
                ),
            )
        )

    if not meshes:
        raise RuntimeError(
            f"No face instances of '{link_name}' were found under '{emitter_name}'."
        )
    return meshes


def mesh_bounds(meshes: Iterable[tuple[str, bpy.types.Mesh]]) -> tuple[Vector, Vector]:
    minimum = Vector((float("inf"), float("inf"), float("inf")))
    maximum = Vector((float("-inf"), float("-inf"), float("-inf")))
    vertex_count = 0
    for _, mesh in meshes:
        for vertex in mesh.vertices:
            minimum.x = min(minimum.x, vertex.co.x)
            minimum.y = min(minimum.y, vertex.co.y)
            minimum.z = min(minimum.z, vertex.co.z)
            maximum.x = max(maximum.x, vertex.co.x)
            maximum.y = max(maximum.y, vertex.co.y)
            maximum.z = max(maximum.z, vertex.co.z)
            vertex_count += 1
    if vertex_count == 0:
        raise RuntimeError("Cannot export an asset without vertices.")
    return minimum, maximum


def object_bounds(objects: Iterable[bpy.types.Object]) -> tuple[Vector, Vector]:
    minimum = Vector((float("inf"), float("inf"), float("inf")))
    maximum = Vector((float("-inf"), float("-inf"), float("-inf")))
    vertex_count = 0
    for obj in objects:
        for vertex in obj.data.vertices:
            coordinate = obj.matrix_world @ vertex.co
            minimum.x = min(minimum.x, coordinate.x)
            minimum.y = min(minimum.y, coordinate.y)
            minimum.z = min(minimum.z, coordinate.z)
            maximum.x = max(maximum.x, coordinate.x)
            maximum.y = max(maximum.y, coordinate.y)
            maximum.z = max(maximum.z, coordinate.z)
            vertex_count += 1
    if vertex_count == 0:
        raise RuntimeError("Cannot calculate bounds for an empty object group.")
    return minimum, maximum


def remove_previous_export(output_dir: Path, asset_id: str) -> None:
    """Only replace outputs owned by this exporter; leave unrelated assets alone."""
    for suffix in (".glb", ".obj", ".mtl"):
        destination = output_dir / f"{asset_id}{suffix}"
        if destination.exists():
            destination.unlink()


def select_only(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def export_glb(output_path: Path, objects: list[bpy.types.Object]) -> None:
    select_only(objects)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        check_existing=False,
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=True,
        export_yup=True,
        export_apply=True,
    )


def export_obj(output_path: Path, objects: list[bpy.types.Object]) -> None:
    """Optional, native Blender-axis diagnostic export for simple OBJ loaders."""
    select_only(objects)
    bpy.ops.wm.obj_export(
        filepath=str(output_path),
        check_existing=False,
        forward_axis="NEGATIVE_Y",
        up_axis="Z",
        global_scale=1.0,
        apply_modifiers=False,
        apply_transform=False,
        export_selected_objects=True,
        export_uv=True,
        export_normals=True,
        export_materials=True,
        export_triangulated_mesh=True,
        export_object_groups=True,
        export_material_groups=True,
    )


def read_glb_document(output_path: Path) -> dict[str, object]:
    if not output_path.is_file():
        raise RuntimeError(f"GLB exporter did not create {output_path.name}.")
    contents = output_path.read_bytes()
    if len(contents) < 20:
        raise RuntimeError(f"{output_path.name} is too small to be a GLB file.")

    magic, version, total_length = struct.unpack_from("<4sII", contents, 0)
    if magic != b"glTF" or version != 2 or total_length != len(contents):
        raise RuntimeError(f"{output_path.name} has an invalid GLB header.")
    json_length, chunk_type = struct.unpack_from("<I4s", contents, 12)
    if chunk_type != b"JSON":
        raise RuntimeError(f"{output_path.name} has no JSON chunk.")
    return json.loads(contents[20 : 20 + json_length].decode("utf-8"))


def verify_glb(output_path: Path, expected_nodes: list[str]) -> dict[str, int]:
    document = read_glb_document(output_path)

    names = {}
    for node in document.get("nodes", []):
        name = node.get("name")
        if name:
            names[name] = names.get(name, 0) + 1
    missing_nodes = sorted(name for name in expected_nodes if names.get(name, 0) == 0)
    if missing_nodes:
        raise RuntimeError(
            f"{output_path.name} is missing expected nodes: {', '.join(missing_nodes)}."
        )
    duplicate_nodes = sorted(name for name, count in names.items() if count > 1)
    if duplicate_nodes:
        raise RuntimeError(
            f"{output_path.name} has duplicate node names: {', '.join(duplicate_nodes)}."
        )
    if not document.get("meshes") or not document.get("materials"):
        raise RuntimeError(f"{output_path.name} is missing mesh or material data.")

    accessors = document.get("accessors", [])
    triangle_count = 0
    for mesh in document["meshes"]:
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                raise RuntimeError(f"{output_path.name} contains a non-triangle primitive.")
            attributes = primitive.get("attributes", {})
            if "POSITION" not in attributes or "NORMAL" not in attributes:
                raise RuntimeError(
                    f"{output_path.name} contains a primitive without position or normal data."
                )
            if "indices" not in primitive:
                raise RuntimeError(f"{output_path.name} contains a non-indexed primitive.")
            index_count = accessors[primitive["indices"]]["count"]
            if index_count % 3 != 0:
                raise RuntimeError(f"{output_path.name} has a non-triangular index count.")
            triangle_count += index_count // 3

    return {
        "glb_mesh_count": len(document["meshes"]),
        "glb_node_count": len(document.get("nodes", [])),
        "triangle_count": triangle_count,
    }


def verify_obj(output_dir: Path, asset_id: str) -> None:
    obj_path = output_dir / f"{asset_id}.obj"
    mtl_path = output_dir / f"{asset_id}.mtl"
    if not obj_path.is_file() or not mtl_path.is_file():
        raise RuntimeError(f"Exporter did not create both OBJ and MTL for '{asset_id}'.")

    vertex_count = 0
    normal_count = 0
    face_count = 0
    non_triangular_faces = 0
    material_library = False
    with obj_path.open("r", encoding="utf-8") as obj_file:
        for line in obj_file:
            if line.startswith("v "):
                vertex_count += 1
            elif line.startswith("vn "):
                normal_count += 1
            elif line.startswith("f "):
                face_count += 1
                if len(line.split()) != 4:
                    non_triangular_faces += 1
            elif line.strip() == f"mtllib {asset_id}.mtl":
                material_library = True
    if (
        vertex_count == 0
        or normal_count == 0
        or face_count == 0
        or non_triangular_faces != 0
        or not material_library
    ):
        raise RuntimeError(
            f"OBJ verification failed for '{asset_id}' "
            f"(vertices={vertex_count}, normals={normal_count}, faces={face_count}, "
            f"non_triangles={non_triangular_faces}, mtllib={material_library})."
        )


def vector_values(vector: Vector) -> list[float]:
    return [round(value, 6) for value in vector]


def blender_to_gltf(vector: Vector) -> list[float]:
    """Convert Blender X/Y/Z axes to glTF X/Y/Z with export_yup enabled."""
    return [round(vector.x, 6), round(vector.z, 6), round(-vector.y, 6)]


def gltf_bounds(minimum: Vector, maximum: Vector) -> tuple[Vector, Vector]:
    """Transform Blender AABB corners into the GLB coordinate convention."""
    return (
        Vector((minimum.x, minimum.z, -maximum.y)),
        Vector((maximum.x, maximum.z, -minimum.y)),
    )


def bounds_metadata(minimum: Vector, maximum: Vector) -> dict[str, list[float]]:
    gltf_minimum, gltf_maximum = gltf_bounds(minimum, maximum)
    return {
        "min": vector_values(gltf_minimum),
        "max": vector_values(gltf_maximum),
        "size": vector_values(gltf_maximum - gltf_minimum),
    }


def source_camera_metadata() -> dict[str, object] | None:
    camera = bpy.context.scene.camera
    if camera is None:
        return None
    return {
        "name": camera.name,
        "location": vector_values(camera.location),
        "rotation_euler": vector_values(camera.rotation_euler),
        "type": camera.data.type,
        "lens": round(camera.data.lens, 6),
    }


def prepare_asset(
    spec: AssetSpec,
    depsgraph: bpy.types.Depsgraph,
    temporary_collection: bpy.types.Collection,
    node_offset: Vector | None = None,
) -> PreparedAsset:
    if spec.source_kind == "face_instances":
        world_meshes = world_meshes_for_face_instances(spec, depsgraph)
    else:
        world_meshes = world_meshes_for_objects(spec.source_objects, depsgraph, spec.asset_id)

    source_minimum, source_maximum = mesh_bounds(world_meshes)
    source_center = (source_minimum + source_maximum) * 0.5
    localize = Matrix.Translation(-source_center)
    material = prepare_material(spec)
    node_offset = node_offset.copy() if node_offset is not None else Vector()
    objects = []

    for component_name, mesh in world_meshes:
        mesh.transform(localize)
        if spec.is_suit:
            # Curves arrive as horizontal Blender XY surfaces. Rotate them to
            # a vertical, +Z-facing glTF convention before export_yup converts
            # the axes, so the scene can hang them without an extra fix-up.
            mesh.transform(SUIT_ORIENTATION)
        mesh.materials.clear()
        mesh.materials.append(material)
        object_name = spec.asset_id if len(world_meshes) == 1 else f"{spec.asset_id}_{component_name}"
        mesh.name = f"{object_name}_mesh"
        obj = bpy.data.objects.new(object_name, mesh)
        obj.location = node_offset
        temporary_collection.objects.link(obj)
        objects.append(obj)

    local_minimum, local_maximum = mesh_bounds([(obj.name, obj.data) for obj in objects])
    return PreparedAsset(
        spec=spec,
        source_center=source_center,
        objects=objects,
        local_minimum=local_minimum,
        local_maximum=local_maximum,
        node_offset=node_offset,
    )


def prepared_metadata(prepared: PreparedAsset) -> dict[str, object]:
    return {
        "id": prepared.spec.asset_id,
        "node_names": [obj.name for obj in prepared.objects],
        "material": prepared.spec.material_name,
        "source_objects": list(prepared.spec.source_objects),
        "source_kind": prepared.spec.source_kind,
        "source_aabb_center": vector_values(prepared.source_center),
        "glb_node_offset": blender_to_gltf(prepared.node_offset),
        "vertex_count": sum(len(obj.data.vertices) for obj in prepared.objects),
        "triangle_count": sum(len(obj.data.polygons) for obj in prepared.objects),
        "local_bounds": bounds_metadata(prepared.local_minimum, prepared.local_maximum),
    }


def remove_prepared_assets(prepared_assets: Iterable[PreparedAsset]) -> None:
    for prepared in prepared_assets:
        for obj in prepared.objects:
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.meshes.remove(mesh)


def require_layout_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.get(name)
    if collection is None:
        raise RuntimeError(
            f"Missing Blender collection '{name}'. Open kingbattle_layout.blend or create it first."
        )
    if not collection.all_objects:
        raise RuntimeError(f"Blender collection '{name}' is empty.")
    return collection


def named_node_indices(document: dict[str, object]) -> dict[str, int]:
    nodes = document.get("nodes", [])
    result = {}
    for index, node in enumerate(nodes):
        name = node.get("name")
        if not isinstance(name, str) or not name:
            continue
        if name in result:
            raise RuntimeError(f"Authored scene has duplicate node name '{name}'.")
        result[name] = index
    return result


def descendants_have_mesh(nodes: list[dict[str, object]], index: int) -> bool:
    node = nodes[index]
    if "mesh" in node:
        return True
    return any(descendants_have_mesh(nodes, child) for child in node.get("children", []))


def verify_authored_scene(document: dict[str, object]) -> None:
    nodes = document.get("nodes", [])
    if not isinstance(nodes, list):
        raise RuntimeError("GLB nodes must be an array.")
    indices = named_node_indices(document)
    missing = [name for name in REQUIRED_NODES if name not in indices]
    if missing:
        raise RuntimeError(f"Authored scene is missing required nodes: {', '.join(missing)}.")

    scene_index = document.get("scene", 0)
    scenes = document.get("scenes", [])
    if not isinstance(scene_index, int) or scene_index < 0 or scene_index >= len(scenes):
        raise RuntimeError("GLB has no valid default scene.")
    if indices[SCENE_ROOT] not in scenes[scene_index].get("nodes", []):
        raise RuntimeError(f"'{SCENE_ROOT}' must be a root node of the default GLB scene.")

    root_children = set(nodes[indices[SCENE_ROOT]].get("children", []))
    required_root_children = {
        "cage",
        "anchor_camera",
        "anchor_camera_target",
        "anchor_fountain",
        *(f"pendant_{suit}" for suit in SUITS),
    }
    for name in required_root_children:
        if indices[name] not in root_children:
            raise RuntimeError(f"'{name}' must be a direct child of '{SCENE_ROOT}'.")

    for suit in SUITS:
        pendant_children = set(nodes[indices[f"pendant_{suit}"]].get("children", []))
        for child_name in (f"chain_{suit}", suit):
            if indices[child_name] not in pendant_children:
                raise RuntimeError(
                    f"'{child_name}' must be a direct child of 'pendant_{suit}'."
                )
        for mesh_node in (f"chain_{suit}", suit):
            if not descendants_have_mesh(nodes, indices[mesh_node]):
                raise RuntimeError(f"'{mesh_node}' must contain a renderable mesh descendant.")

    if not descendants_have_mesh(nodes, indices["cage"]):
        raise RuntimeError("'cage' must contain a renderable mesh descendant.")
    for anchor in ("anchor_camera", "anchor_camera_target", "anchor_fountain"):
        if descendants_have_mesh(nodes, indices[anchor]):
            raise RuntimeError(f"'{anchor}' is an anchor and may not contain a mesh.")

    material_names = {
        material.get("name")
        for material in document.get("materials", [])
        if material.get("name")
    }
    missing_materials = sorted(REQUIRED_MATERIALS - material_names)
    if missing_materials:
        raise RuntimeError(
            f"Authored scene is missing required materials: {', '.join(missing_materials)}."
        )


def authored_scene_metadata(
    output_dir: Path,
    collection: bpy.types.Collection,
) -> dict[str, object]:
    objects = list(collection.all_objects)
    mesh_objects = [object_ for object_ in objects if object_.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError(f"Blender collection '{collection.name}' has no mesh objects.")

    for asset_id in ("cage", "chain", "suits", "kingbattle_scene"):
        remove_previous_export(output_dir, asset_id)
    glb_path = output_dir / SCENE_FILE
    export_glb(glb_path, objects)
    verification = verify_glb(glb_path, list(REQUIRED_NODES))
    document = read_glb_document(glb_path)
    verify_authored_scene(document)

    minimum, maximum = object_bounds(mesh_objects)
    material_names = sorted(
        material.get("name")
        for material in document.get("materials", [])
        if material.get("name")
    )
    return {
        "file": glb_path.name,
        "collection": collection.name,
        "root": SCENE_ROOT,
        "required_nodes": list(REQUIRED_NODES),
        "material_names": material_names,
        "vertex_count": sum(len(object_.data.vertices) for object_ in mesh_objects),
        "local_bounds": bounds_metadata(minimum, maximum),
        **verification,
    }


def main() -> None:
    args = parse_args()
    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if not bpy.data.filepath:
        raise RuntimeError("Open kingbattle_layout.blend before running this exporter.")

    collection = require_layout_collection(args.collection)
    scene_metadata = authored_scene_metadata(output_dir, collection)
    manifest = {
        "format_version": 2,
        "source_blend": Path(bpy.data.filepath).name,
        "blender_version": bpy.app.version_string,
        "coordinate_system": {
            "format": "glTF 2.0 binary (.glb)",
            "handedness": "right",
            "right": "+X",
            "forward": "-Z",
            "up": "+Y",
            "units": "Blender scene units",
            "asset_origin": SCENE_ROOT,
            "scene_layout": "Blender collection hierarchy",
        },
        "authored_scene": scene_metadata,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Exported Blender-authored scene to {output_dir / SCENE_FILE}: "
        f"{scene_metadata['glb_mesh_count']} meshes, "
        f"{scene_metadata['triangle_count']} triangles."
    )


if __name__ == "__main__":
    main()
