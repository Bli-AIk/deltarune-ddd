-- Blender-first preset consumed by libraries/ddd-3d.
-- Static transforms, hierarchy, and camera anchors live in kingbattle_scene.glb.
return {
    version = 2,

    materials = {
        cage_metal = {
            name = "kingbattle_cage_metal",
            shader = "lit",
            base_color = { 0.24, 0.24, 0.56, 1.0 },
            emissive = { 0.035, 0.012, 0.130 },
            metallic = 0.88,
            roughness = 0.30,
            double_sided = true,
        },
        chain_metal = {
            name = "kingbattle_chain_metal",
            shader = "lit",
            base_color = { 0.46, 0.43, 0.78, 1.0 },
            emissive = { 0.070, 0.020, 0.230 },
            metallic = 0.91,
            roughness = 0.24,
            double_sided = true,
        },
        suit_dark_metal = {
            name = "kingbattle_suit_dark_metal",
            shader = "lit",
            base_color = { 0.45, 0.23, 0.80, 1.0 },
            emissive = { 0.160, 0.020, 0.430 },
            metallic = 0.73,
            roughness = 0.27,
            double_sided = true,
        },
        suit_red_metal = {
            name = "kingbattle_suit_red_metal",
            shader = "lit",
            base_color = { 0.85, 0.08, 0.35, 1.0 },
            emissive = { 0.250, 0.010, 0.130 },
            metallic = 0.66,
            roughness = 0.31,
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
            suit_dark_metal = "suit_dark_metal",
            suit_red_metal = "suit_red_metal",
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
