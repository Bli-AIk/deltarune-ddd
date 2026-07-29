# DDD 3D Assets

`kingbattle/kingbattle_layout.blend` is the authority for the full King Battle
background: cage, chains, card suits, camera anchors, and all static
transforms. Do all scene composition in the `DDD_KINGBATTLE` collection in
Blender. Lua only selects shader parameters by material name.

After editing the layout, export it from the mod root:

```sh
blender --background assets/3d/kingbattle/kingbattle_layout.blend \
  --python tools/export_ddd_assets.py -- --output assets/3d/kingbattle
```

The exporter validates and emits `kingbattle_scene.glb`; it never lays out,
repositions, rotates, or scales scene objects. `manifest.json` records the
resulting GLB contract.

The visual-style migration is idempotent and can be reapplied to an existing
layout when source geometry is refreshed:

```sh
blender --background assets/3d/kingbattle/kingbattle_layout.blend \
  --python tools/apply_kingbattle_layout_style.py
```

The material contract is deliberately small:

| Material | Authored role |
| --- | --- |
| `cage_metal` | purple-tinted cage metal |
| `chain_metal` | purple-tinted chain metal |
| `suit_edge` | purple tubes along the model's real feature edges |
| `suit_fill` | opaque black extruded symbol body |
