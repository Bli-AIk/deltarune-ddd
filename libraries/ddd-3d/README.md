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
`NORMAL`, `TEXCOORD_0`, optional `TANGENT`, optional indices, glTF materials,
and node transforms.
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

Supported instance motion kinds are `bob`, `spin`, `pulse`, and `sway`.
`chain_sway` is reserved for Blender-authored hierarchy scenes.

## Authored Hierarchy Motion

An authored GLB may animate named, Blender-authored hierarchy nodes without
moving scene placement into Lua. Declare each node in `required_nodes`, then
attach a data-only motion entry. `sway` composes a primary pendulum rotation
with an optional small secondary twist; varying speeds and phases provides
repeatable, non-synchronous motion without relying on global random state.

```lua
authored_scene = {
    -- Path, root, camera, and material overrides omitted.
    required_nodes = { "scene_root", "pendulum_pivot" },
    motions = {
        {
            node = "pendulum_pivot",
            kind = "sway",
            axis = {0, 0, 1},
            amplitude = 0.03,
            speed = 0.55,
            secondary_axis = {0, 1, 0},
            secondary_amplitude = 0.01,
            secondary_speed = 1.1,
        },
    },
}
```

The pivot and its children remain fully editable in Blender. Any chain, prop,
or character parented below that pivot follows the same motion automatically.

### Articulated Chain Response

`chain_sway` animates an authored terminal and every tagged chain link without
declaring link positions or node lists in Lua. The terminal uses `axis` in its
parent space; each link uses `link_axis` in the chain node's local space. Both
angles are sinusoidal and bounded, so they slow at the configured limit and
reverse rather than continuously spinning.

```lua
authored_scene = {
    -- Path, root, camera, and material overrides omitted.
    required_nodes = { "chain", "hanging_symbol" },
    motions = {
        {
            node = "chain",
            kind = "chain_sway",
            terminal = "hanging_symbol",
            axis = {0, 1, 0},
            amplitude = math.rad(40),
            speed = 1.3,
            phase = 0.7,
            link_axis = {0, 1, 0},
            link_amplitude = math.rad(24),
            link_phase_lag = 0.7,
            link_min_weight = 0.08,
            link_curve = 1.35,
        },
    },
}
```

In Blender, tag each link object with custom properties
`ddd_role = "chain_link"` and a dense zero-based `ddd_link_index`. The GLB
loader retains these extras and orders the response by the authored index.
This makes the chain topology and rest layout Blender-owned while the library
only applies the declared dynamic behavior.

## Materials

The built-in `lit` shader uses a compact metallic workflow with directional
lighting and an ambient reflection approximation. `metallic` and `roughness`
follow glTF conventions. `specular_strength` and `ambient_reflection` are
optional, clamped `0..1` controls; both default to values that keep metal
legible in a low-key scene. The camel-case aliases `specularStrength` and
`ambientReflection` are accepted when a project uses that convention.

Material maps can be declared globally in `materials`, referenced by instance
material id, or used as `assets.<id>.material_overrides.<gltf_material_name>`.
For a Blender-authored scene, map each source material name exactly once:

```lua
authored_scene = {
    -- Other authored-scene fields omitted.
    material_overrides = {
        suit_outline_metal = "purple_outline",
        suit_fill_black = "black_fill",
    },
}
```

The runtime checks that every authored source material exists exactly once in
the GLB before spawning the authored scene. Double-sided materials keep their
normal back-face behavior; `ambient_reflection` supplies the restrained
directional reflection used to keep cage interiors and chain links readable.

`lit` additionally accepts optional texture paths:

```lua
materials = {
    aged_metal = {
        shader = "lit",
        normal_texture = "textures/metal_nor_gl.jpg",
        roughness_texture = "textures/metal_rough.jpg",
        normal_strength = 0.22,
        uv_scale = { 1.0, 1.0 },
    },
}
```

`base_color_texture` (aliases: `baseColorTexture`, `albedo_texture`, and
`texture`), `normal_texture` / `normalMap`, and `roughness_texture` /
`roughnessMap` are supported. The runtime resolves relative texture paths
against `context.asset_root`; absolute paths are loaded through LÖVE FileData
so Kristal mod asset roots work without changing the virtual filesystem.
Missing GLB tangents are generated from positions, normals, and UVs; Blender
exports should still include `TANGENT` when a normal map is authored.

Scenes may define a low-intensity fill directional light independently of the
key light. This is useful for an interior such as a cage, where a second
reflection should reveal the far side without making every back face bright:

```lua
scene = {
    light = {
        direction = { -0.3, -0.7, -0.5 },
        color = { 0.8, 0.6, 1.0 },
        ambient = { 0.16, 0.08, 0.28 },
        fill = {
            direction = { 0.4, -0.3, 0.7 },
            color = { 0.3, 0.15, 0.6 },
            strength = 0.16,
        },
    },
}
```

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
