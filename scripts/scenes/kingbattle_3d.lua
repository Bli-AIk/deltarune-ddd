-- Blender-first preset consumed by libraries/ddd-3d.
-- Static transforms, hierarchy, and camera anchors live in kingbattle_scene.glb.
local metal_surface = {
    albedo = "textures/blue_metal_plate_diff_1k.jpg",
    normal = "textures/blue_metal_plate_nor_gl_1k.jpg",
    roughness = "textures/blue_metal_plate_rough_1k.jpg",
}
local degree = math.pi / 180
-- Keep the authored motion relationships while making the scene settle more slowly.
local motion_speed_scale = 0.60
-- Motion vectors are node-local Blender axes. The pendant roots use local X;
-- the chain, suit, and link nodes use local Z. These are the authored axes
-- for their shared vertical-plane motion; the vertical chain axis is excluded.
local pendant_vertical_plane_axis = { 1.0, 0.0, 0.0 }
local suit_and_link_vertical_plane_axis = { 0.0, 0.0, 1.0 }

return {
    version = 2,

    materials = {
        cage_metal = {
            name = "kingbattle_cage_metal",
            shader = "lit",
            base_color = { 0.16, 0.20, 0.44, 1.0 },
            emissive = { 0.004, 0.008, 0.030 },
            metallic = 0.76,
            roughness = 0.45,
            specular_strength = 0.42,
            ambient_reflection = 0.48,
            base_color_texture = metal_surface.albedo,
            normal_texture = metal_surface.normal,
            roughness_texture = metal_surface.roughness,
            normal_strength = 0.22,
            uv_scale = { 1.45, 1.45 },
            double_sided = true,
        },
        chain_metal = {
            name = "kingbattle_chain_metal",
            shader = "lit",
            base_color = { 0.28, 0.32, 0.52, 1.0 },
            emissive = { 0.075, 0.090, 0.22 },
            metallic = 0.48,
            roughness = 0.36,
            specular_strength = 0.44,
            ambient_reflection = 0.48,
            base_color_texture = metal_surface.albedo,
            normal_texture = metal_surface.normal,
            roughness_texture = metal_surface.roughness,
            normal_strength = 0.18,
            uv_scale = { 1.25, 1.25 },
            double_sided = true,
        },
        background_wall = {
            name = "kingbattle_background_wall",
            shader = "lit",
            base_color = { 0.030, 0.012, 0.095, 1.0 },
            emissive = { 0.002, 0.0005, 0.014 },
            metallic = 0.08,
            roughness = 0.86,
            specular_strength = 0.15,
            ambient_reflection = 0.14,
            base_color_texture = metal_surface.albedo,
            normal_texture = metal_surface.normal,
            roughness_texture = metal_surface.roughness,
            normal_strength = 0.14,
            uv_scale = { 1.35, 0.90 },
            double_sided = true,
        },
        suit_edge = {
            name = "kingbattle_suit_edge",
            shader = "lit",
            -- These may be written as "#RRGGBB" or "#RRGGBBAA" while tuning.
            base_color = "#512E88",
            emissive = "#5A4DA0",
            metallic = 0.30,
            roughness = 0.18,
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
        -- The GLB keeps the editable Blender layout in native Z-up space.
        -- ddd-3d performs the one explicit B(x, y, z) -> E(x, -z, -y)
        -- conversion while instantiating the authored scene.
        coordinate_space = "blender_z_up",
        root = "DDD_SCENE_ROOT",
        required_nodes = {
            "DDD_SCENE_ROOT",
            "environment_shell",
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
            "light_cage_left",
            "light_cage_right",
            "light_cage_back",
            "light_cage_floor",
        },
        material_overrides = {
            background_wall = "background_wall",
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
        point_lights = {
            {
                node = "light_cage_left",
                color = { 0.14, 0.08, 0.52 },
                strength = 2.8,
                range = 24.0,
            },
            {
                node = "light_cage_right",
                color = { 0.30, 0.08, 0.72 },
                strength = 2.4,
                range = 24.0,
            },
            {
                node = "light_cage_back",
                color = { 0.045, 0.055, 0.28 },
                strength = 1.8,
                range = 22.0,
            },
            {
                node = "light_cage_floor",
                color = { 0.15, 0.07, 0.38 },
                strength = 1.1,
                range = 18.0,
            },
        },
        motions = {
            -- The vertical chain axis stays fixed. Both layers turn around
            -- the horizontal axis contained in the authored vertical plane.
            {
                node = "pendant_club",
                kind = "sway",
                axis = pendant_vertical_plane_axis,
                amplitude = 2.2 * degree,
                speed = 0.62 * motion_speed_scale,
                phase = 0.65,
            },
            {
                node = "pendant_spade",
                kind = "sway",
                axis = pendant_vertical_plane_axis,
                amplitude = 1.8 * degree,
                speed = 0.78 * motion_speed_scale,
                phase = 3.55,
            },
            {
                node = "pendant_heart",
                kind = "sway",
                axis = pendant_vertical_plane_axis,
                amplitude = 2.5 * degree,
                speed = 0.70 * motion_speed_scale,
                phase = 4.75,
            },
            {
                node = "pendant_diamond",
                kind = "sway",
                axis = pendant_vertical_plane_axis,
                amplitude = 2.0 * degree,
                speed = 0.88 * motion_speed_scale,
                phase = 2.10,
            },
            {
                node = "chain_club",
                kind = "chain_sway",
                terminal = "club",
                axis = suit_and_link_vertical_plane_axis,
                amplitude = 41 * degree,
                speed = 1.25 * motion_speed_scale,
                phase = 0.65,
                link_axis = suit_and_link_vertical_plane_axis,
                link_amplitude = 25 * degree,
                link_phase_lag = 0.70,
                link_min_weight = 0.07,
                link_curve = 1.40,
            },
            {
                node = "chain_spade",
                kind = "chain_sway",
                terminal = "spade",
                axis = suit_and_link_vertical_plane_axis,
                amplitude = 39 * degree,
                speed = 1.55 * motion_speed_scale,
                phase = 3.55,
                link_axis = suit_and_link_vertical_plane_axis,
                link_amplitude = 22 * degree,
                link_phase_lag = 0.58,
                link_min_weight = 0.09,
                link_curve = 1.25,
            },
            {
                node = "chain_heart",
                kind = "chain_sway",
                terminal = "heart",
                axis = suit_and_link_vertical_plane_axis,
                amplitude = 45 * degree,
                speed = 1.35 * motion_speed_scale,
                phase = 4.75,
                link_axis = suit_and_link_vertical_plane_axis,
                link_amplitude = 27 * degree,
                link_phase_lag = 0.76,
                link_min_weight = 0.06,
                link_curve = 1.45,
            },
            {
                node = "chain_diamond",
                kind = "chain_sway",
                terminal = "diamond",
                axis = suit_and_link_vertical_plane_axis,
                amplitude = 42 * degree,
                speed = 1.65 * motion_speed_scale,
                phase = 2.10,
                link_axis = suit_and_link_vertical_plane_axis,
                link_amplitude = 23 * degree,
                link_phase_lag = 0.64,
                link_min_weight = 0.08,
                link_curve = 1.32,
            },
        },
    },

    -- The first 2D camera position received by the runtime is the follow origin;
    -- these values only control the subtle 3D response to horizontal travel.
    camera_follow = {
        kind = "camera_x",
        reference_distance = 160.0,
        position_offset = { 0.24, 0.00, 0.00 },
        target_offset = { 0.10, 0.00, 0.00 },
        yaw = 2.4 * degree,
        smoothing = 7.0,
    },

    scene = {
        clear_color = { 0.006, 0.001, 0.016, 1.0 },
        light = {
            -- The authored key ray runs from the upper-left, camera-facing
            -- side into the cage. Directions are ray travel, while the shader
            -- derives its lighting vector as -direction.
            direction = { -0.30, 0.58, 0.76 },
            color = { 0.34, 0.42, 0.82, 1.0 },
            ambient = { 0.036, 0.054, 0.125, 1.0 },
            fill = {
                direction = { 0.46, 0.32, -0.72 },
                color = { 0.11, 0.15, 0.34 },
                strength = 0.16,
            },
        },
    },

    output = {
        clear_color = { 0.006, 0.001, 0.016, 1.0 },
        fog = {
            color = { 0.010, 0.003, 0.030 },
            strength = 0.095,
        },
        vignette = 0.22,
        bloom = {
            threshold = 0.16,
            soft_knee = 0.10,
            strength = 1.25,
            radius = 1.0,
            scale = 0.50,
            tint = { 0.62, 0.24, 1.0 },
        },
    },
}
