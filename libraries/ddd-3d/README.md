# ddd-3d

`ddd-3d` is a self-contained Kristal library for small glTF 2.0 / GLB scenes.
It owns GPU meshes, shaders, color/depth Canvas targets, and render-state
restoration. It does not depend on a map, encounter, controller, or asset name.

## Direct API

```lua
local DDD3D = Mod.libs["ddd-3d"]
local scene = assert(DDD3D.newScene({ camera = { position = {0, 4, 12} } }))
local model = assert(DDD3D.loadGLB(Mod.info.path .. "/assets/models/example.glb"))
assert(DDD3D.spawn(scene, model, { node = "named_subtree" }))
assert(DDD3D.update(scene, DT))
assert(DDD3D.draw(scene))
```

`loadGLB` supports Blender-exported `TRIANGLES` primitives with `POSITION`,
`NORMAL`, `TEXCOORD_0`, optional indices, glTF materials, and node transforms.
`Model:instantiate({ node = "name" })` and `spawn(..., { node = "name" })`
clone just that named source subtree while sharing GPU mesh data.

## Declarative Runtime

Use the runtime when a controller should only forward data and lifecycle calls.
Definitions are data-only and are deep-copied by the library, so preset modules
can safely cache and reuse their tables.

```lua
local definition = {
    version = 1,
    scene = {
        camera = { position = {0, 7, 14}, target = {0, 0, 0}, fov = math.rad(45) },
        light = { direction = {-0.3, -0.7, -0.5}, ambient = {0.2, 0.2, 0.25} },
    },
    assets = {
        model = { path = "assets/models/example.glb" },
    },
    instances = {
        {
            id = "example",
            asset = "model",
            node = "named_subtree",
            transform = { position = {0, 0, 0}, scale = {1, 1, 1} },
            motion = { kind = "bob", axis = {0, 1, 0}, amplitude = 0.25, speed = 1 },
        },
    },
    output = { vignette = 0.15 },
}

assert(DDD3D.validateDefinition(definition))
local runtime = assert(DDD3D.newRuntime(definition))
assert(runtime:update(DT))
assert(runtime:draw())
```

Supported instance motion kinds are `bob`, `spin`, and `pulse`. Material maps
can be declared globally in `materials`, referenced by instance material id, or
used as `assets.<id>.material_overrides.<gltf_material_name>`.

## World Camera Rig

Controllers should capture a numeric world-camera snapshot, not calculate 3D
camera transforms. A `map_follow` camera rig maps the snapshot onto `xy`, `xz`,
or `yz` with declarative origin and offsets.

```lua
definition.camera_rig = {
    kind = "map_follow",
    map_plane = "xz",
    map_scale = 1,
    world_origin = {0, 0, 0},
    position_offset = {0, 8, 12},
    target_offset = {0, 0, 0},
    zoom_mode = "fov",
}

local context = assert(DDD3D.captureWorldContext(Game.world))
assert(runtime:update(DT, context))
```

## Resource Ownership

`runtime:release()` releases its scene, loaded models, and runtime-created
materials. For the direct API, release the scene and models when their owner is
finished. Every public operation reports recoverable failures as `nil, err`.

The renderer owns a separate color Canvas and depth Canvas, probes usable depth
formats, and restores depth mode, mesh cull mode, front-face winding, and the
caller's target Canvas after both success and failure.
