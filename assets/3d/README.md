# DDD 3D Assets

`kingbattle/kingbattle_layout.blend` is the authority for the full King Battle
background: cage, chains, card suits, camera anchors, and all static
transforms. Do all scene composition in the `DDD_KINGBATTLE` collection in
Blender. Lua only selects shader parameters by material name.

Opening the file lands in `DDD_KINGBATTLE_AUTHORING`, which contains only the
exportable layout plus `DDD_AUTHORING_GUIDES` and its camera. The supplied raw
cage, chain, and suit source objects live in the separate
`DDD_SOURCE_REFERENCE` scene, so they cannot be accidentally exported or
edited as part of the staged background.

The layout uses ordinary Blender axes: `+X` is right, `-Y` is the authoring
camera's forward direction, and `+Z` is up. Keep positions, rotations, scales,
parenting, camera anchors, and chain rest poses in that space. The exporter
preserves those transforms in the GLB, while `ddd-3d` applies exactly one
runtime conversion, `B(x, y, z) -> E(x, -z, -y)`, selected by
`coordinate_space = "blender_z_up"` in `kingbattle_3d.lua`. Do not add a
second root rotation, negative scale, or Lua-side coordinate correction.

After editing the layout, export it from the mod root:

```sh
blender --background assets/3d/kingbattle/kingbattle_layout.blend \
  --python tools/export_ddd_assets.py -- --output assets/3d/kingbattle
```

The exporter validates and emits `kingbattle_scene.glb`; it never lays out,
repositions, rotates, scales, or remaps scene objects. It also verifies that
the exported required-node matrices exactly match Blender local transforms.
`manifest.json` records the resulting GLB contract.

`kingbattle/textures/` contains the shared PBR maps used by the cage and
chains. Those maps are connected in the editable Blender materials, while
`scripts/scenes/kingbattle_3d.lua` selects the matching runtime normal and
roughness maps. Static transforms stay in Blender in both cases. The
one-time bootstrap, style, and refinement scripts use the `.bak` suffix and
are archival only; edit the `.blend` directly, then run the exporter above.

The material contract is deliberately small:

| Material | Authored role |
| --- | --- |
| `background_wall` | low-contrast deep-blue textured enclosure outside the cage |
| `cage_metal` | deep-blue weathered cage metal |
| `chain_metal` | darker weathered chain metal |
| `suit_edge` | purple tubes along the model's real feature edges |
| `suit_fill` | opaque black extruded symbol body |
