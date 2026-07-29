-- Blender-first preset consumed by libraries/ddd-3d.
-- Static transforms, hierarchy, and camera anchors live in kingbattle_scene.glb.
return {
    version = 2,

    materials = {
        cage_metal = {
            name = "kingbattle_cage_metal",
            shader = "lit",
            base_color = { 0.18, 0.16, 0.40, 1.0 },
            emissive = { 0.028, 0.008, 0.105 },
            metallic = 0.62,
            roughness = 0.28,
            double_sided = true,
        },
        chain_metal = {
            name = "kingbattle_chain_metal",
            shader = "lit",
            base_color = { 0.32, 0.27, 0.60, 1.0 },
            emissive = { 0.065, 0.018, 0.210 },
            metallic = 0.72,
            roughness = 0.20,
            double_sided = true,
        },
        suit_edge = {
            name = "kingbattle_suit_edge",
            shader = "lit",
            base_color = { 0.48, 0.05, 0.95, 1.0 },
            emissive = { 0.165, 0.008, 0.510 },
            metallic = 0.38,
            roughness = 0.24,
            double_sided = true,
        },
        suit_fill = {
            name = "kingbattle_suit_fill",
            shader = "lit",
            base_color = { 0.006, 0.003, 0.018, 1.0 },
            emissive = { 0.001, 0.000, 0.006 },
            metallic = 0.16,
            roughness = 0.42,
            double_sided = true,
        },
    },

    authored_scene = {
        path = "kingbattle_scene.glb",
        root = "DDD_SCENE_ROOT",
        required_nodes = {
            "DDD_SCENE_ROOT",
            "cage",
            "pendant_club",
            "chain_club",
            "club",
            "pendant_spade",
            "chain_spade",
            "spade",
            "pendant_heart",
            "chain_heart",
            "heart",
            "pendant_diamond",
            "chain_diamond",
            "diamond",
            "anchor_camera",
            "anchor_camera_target",
            "anchor_fountain",
        },
        material_overrides = {
            cage_metal = "cage_metal",
            chain_metal = "chain_metal",
            suit_edge = "suit_edge",
            suit_fill = "suit_fill",
        },
        camera = {
            anchor = "anchor_camera",
            target_anchor = "anchor_camera_target",
            fov = 0.7853981634,
            near = 0.10,
            far = 96.0,
        },
    },

    scene = {
        clear_color = { 0.006, 0.004, 0.025, 1.0 },
        light = {
            direction = { -0.30, -0.58, -0.76 },
            color = { 0.80, 0.55, 1.00, 1.0 },
            ambient = { 0.180, 0.060, 0.310, 1.0 },
        },
    },

    output = {
        clear_color = { 0.006, 0.004, 0.025, 1.0 },
        fog = {
            color = { 0.030, 0.012, 0.090 },
            strength = 0.045,
        },
        vignette = 0.16,
    },
}
