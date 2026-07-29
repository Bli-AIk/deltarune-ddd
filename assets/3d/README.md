# DDD 3D Assets

The assets in `kingbattle/` are generated from
`/home/aik/Documents/Blender/ddd-8.blend`. Regenerate them from the mod root:

```sh
blender --background /home/aik/Documents/Blender/ddd-8.blend \
  --python tools/export_ddd_assets.py -- --output assets/3d/kingbattle
```

The default deliverables are `cage.glb`, `chain.glb`, and `suits.glb`.
`suits.glb` preserves four named, independently addressable nodes: `club`,
`spade`, `heart`, and `diamond`. Add `--also-obj` to also create native Blender
axis OBJ/MTL files for loader diagnostics.

`manifest.json` is the loader contract. All source curves, modifiers, and face
instances are evaluated and triangulated. Each asset mesh is centered on its
axis-aligned bounding-box center. GLB files use the glTF convention: `+X`
right, `+Y` up, `-Z` forward. Card-suit fronts face `+Z`.

The source has no authored material slots or texture images. Stable material
names (`cage_metal`, `chain_metal`, `suit_dark_metal`, and `suit_red_metal`)
are embedded for the Kristal shader layer to map to its own parameters.

Source mapping:

| Exported group | Blender source |
| --- | --- |
| `cage.glb` | `hori`, `vert` curves in `cage` |
| `chain.glb` | evaluated face instances of `chain` over `chain.001` |
| `suits.glb` | `Curve`, `Curve.001`, `Curve.002`, `Curve.003` |
