-- A deliberately small declarative layer over Scene. It accepts data only,
-- keeping game presets and controllers free from renderer implementation.
local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Scene = libRequire(LIB_ID, "scripts.scene.scene")
local Material = libRequire(LIB_ID, "scripts.scene.material")
local GLBLoader = libRequire(LIB_ID, "scripts.scene.glb_loader")

local Runtime = {}
Runtime.__index = Runtime

local MOTION_KINDS = {
    bob = true,
    spin = true,
    pulse = true,
    sway = true,
    chain_sway = true,
}

-- Composite is library-internal; declarative materials may only select a
-- surface shader that the library ships and compiles for mesh rendering.
local MATERIAL_SHADERS = {
    lit = true,
    emissive = true,
}

local MAP_PLANES = {
    xy = { 1, 2 },
    xz = { 1, 3 },
    yz = { 2, 3 },
}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function path_error(path, message)
    return nil, path .. ": " .. message
end

local function validate_plain_value(value, path, visited)
    local value_type = type(value)
    if value_type == "nil" or value_type == "boolean" or value_type == "string" then
        return true
    end
    if value_type == "number" then
        if finite(value) then
            return true
        end
        return path_error(path, "numbers must be finite")
    end
    if value_type ~= "table" then
        return path_error(path, "definitions may only contain booleans, strings, numbers, and tables")
    end
    if visited[value] then
        return path_error(path, "definitions cannot contain cyclic tables")
    end
    visited[value] = true
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type ~= "string" and key_type ~= "number" then
            visited[value] = nil
            return path_error(path, "table keys must be strings or numbers")
        end
        local valid, err = validate_plain_value(child, path .. "." .. tostring(key), visited)
        if not valid then
            visited[value] = nil
            return nil, err
        end
    end
    visited[value] = nil
    return true
end

local function deep_copy(value, visited)
    if type(value) ~= "table" then
        return value
    end
    visited = visited or {}
    if visited[value] then
        return visited[value]
    end
    local copy = {}
    visited[value] = copy
    for key, child in pairs(value) do
        copy[deep_copy(key, visited)] = deep_copy(child, visited)
    end
    return copy
end

local function validate_vector(value, count, path, optional)
    if value == nil and optional then
        return true
    end
    if type(value) ~= "table" then
        return path_error(path, "must be a vec" .. tostring(count) .. " table")
    end
    for index = 1, count do
        if not finite(value[index]) then
            return path_error(path .. "[" .. tostring(index) .. "]", "must be a finite number")
        end
    end
    return true
end

local function validate_color(value, count, path, optional)
    if type(value) == "string" then
        if Material.isHexColor(value) then
            return true
        end
        return path_error(path, "must be a valid hex color such as #RRGGBB or #RRGGBBAA")
    end
    return validate_vector(value, count, path, optional)
end

local function validate_transform(transform, path)
    if transform == nil then
        return true
    end
    if type(transform) ~= "table" then
        return path_error(path, "must be a table")
    end
    local checks = {
        { transform.position, 3, "position" },
        { transform.rotation, 4, "rotation" },
        { transform.scale, 3, "scale" },
        { transform.matrix, 16, "matrix" },
    }
    for _, check in ipairs(checks) do
        local valid, err = validate_vector(check[1], check[2], path .. "." .. check[3], true)
        if not valid then return nil, err end
    end
    return true
end

local function validate_material_spec(material, path)
    if type(material) ~= "table" then
        return path_error(path, "must be a material table")
    end
    if material.shader ~= nil and (type(material.shader) ~= "string" or not MATERIAL_SHADERS[material.shader]) then
        return path_error(path .. ".shader", "must be lit or emissive")
    end
    local valid, err = validate_color(material.base_color or material.baseColor, 4, path .. ".base_color", true)
    if not valid then return nil, err end
    valid, err = validate_color(material.emissive, 3, path .. ".emissive", true)
    if not valid then return nil, err end
    for _, field in ipairs({
        "metallic",
        "roughness",
        "specular_strength",
        "specularStrength",
        "ambient_reflection",
        "ambientReflection",
        "normal_strength",
        "normalStrength",
        "normal_scale",
        "normalScale",
        "alpha_cutoff",
        "alphaCutoff",
    }) do
        if material[field] ~= nil and not finite(material[field]) then
            return path_error(path .. "." .. field, "must be a finite number")
        end
    end
    valid, err = validate_vector(material.uv_scale or material.uvScale, 2, path .. ".uv_scale", true)
    if not valid then return nil, err end
    local texture_valid, texture_field, texture_err = Material.validateTexturePaths(material)
    if not texture_valid then
        return path_error(path .. "." .. tostring(texture_field), texture_err)
    end
    return true
end

local function validate_dense_array(value, path)
    if type(value) ~= "table" then
        return path_error(path, "must be an array")
    end
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return path_error(path, "must use consecutive positive integer indexes")
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        return path_error(path, "must not be sparse")
    end
    return maximum
end

local function validate_unique_name_array(value, path)
    local count, array_err = validate_dense_array(value, path)
    if not count then return nil, array_err end
    local names = {}
    for index = 1, count do
        local name = value[index]
        if type(name) ~= "string" or name == "" then
            return path_error(path .. "[" .. tostring(index) .. "]", "must be a non-empty string")
        end
        if names[name] then
            return path_error(path .. "[" .. tostring(index) .. "]", "duplicates " .. name)
        end
        names[name] = true
    end
    return names
end

local function validate_authored_scene(specification, materials)
    if type(specification) ~= "table" then
        return path_error("authored_scene", "must be a table")
    end
    if type(specification.path) ~= "string" or specification.path == "" then
        return path_error("authored_scene.path", "must be a non-empty GLB path")
    end
    if specification.coordinate_space ~= nil
        and specification.coordinate_space ~= "gltf_y_up"
        and specification.coordinate_space ~= "blender_z_up"
    then
        return path_error(
            "authored_scene.coordinate_space",
            "must be gltf_y_up or blender_z_up"
        )
    end
    if type(specification.root) ~= "string" or specification.root == "" then
        return path_error("authored_scene.root", "must be a non-empty Blender node name")
    end
    local required_nodes, nodes_err = validate_unique_name_array(
        specification.required_nodes,
        "authored_scene.required_nodes"
    )
    if not required_nodes then return nil, nodes_err end
    if not required_nodes[specification.root] then
        return path_error("authored_scene.required_nodes", "must include authored_scene.root")
    end

    local camera = specification.camera
    if type(camera) ~= "table" then
        return path_error("authored_scene.camera", "must define Blender camera anchors")
    end
    for _, field in ipairs({ "anchor", "target_anchor" }) do
        local name = camera[field]
        if type(name) ~= "string" or name == "" then
            return path_error("authored_scene.camera." .. field, "must be a non-empty node name")
        end
        if not required_nodes[name] then
            return path_error(
                "authored_scene.camera." .. field,
                "must reference an entry in authored_scene.required_nodes"
            )
        end
    end
    for _, field in ipairs({ "fov", "near", "far" }) do
        if camera[field] ~= nil and not finite(camera[field]) then
            return path_error("authored_scene.camera." .. field, "must be a finite number")
        end
    end
    if camera.fov and (camera.fov <= 0 or camera.fov >= math.pi) then
        return path_error("authored_scene.camera.fov", "must be between 0 and pi radians")
    end
    if camera.near and camera.near <= 0 then
        return path_error("authored_scene.camera.near", "must be positive")
    end
    if camera.far and camera.near and camera.far <= camera.near then
        return path_error("authored_scene.camera.far", "must be greater than near")
    end

    local overrides = specification.material_overrides
    if overrides ~= nil and type(overrides) ~= "table" then
        return path_error("authored_scene.material_overrides", "must be a table")
    end
    for source_name, material_id in pairs(overrides or {}) do
        if type(source_name) ~= "string" or source_name == "" then
            return path_error("authored_scene.material_overrides", "keys must be non-empty material names")
        end
        if type(material_id) ~= "string" or not materials or not materials[material_id] then
            return path_error(
                "authored_scene.material_overrides." .. source_name,
                "must reference a declared material id"
            )
        end
    end
    if specification.point_lights ~= nil then
        local point_count, point_err = validate_dense_array(
            specification.point_lights,
            "authored_scene.point_lights"
        )
        if not point_count then return nil, point_err end
        if point_count > 4 then
            return nil, "authored_scene.point_lights supports at most four lights"
        end
        for index = 1, point_count do
            local point = specification.point_lights[index]
            local point_path = "authored_scene.point_lights." .. tostring(index)
            if type(point) ~= "table" or type(point.node) ~= "string" or point.node == "" then
                return path_error(point_path .. ".node", "must be a non-empty authored node name")
            end
            if not required_nodes[point.node] then
                return path_error(point_path .. ".node", "must reference authored_scene.required_nodes")
            end
            local valid, err = validate_vector(point.color, 3, point_path .. ".color", false)
            if not valid then return nil, err end
            for _, field in ipairs({ "strength", "range" }) do
                if point[field] == nil or not finite(point[field]) or point[field] < 0 then
                    return path_error(point_path .. "." .. field, "must be a non-negative number")
                end
            end
            if point.range <= 0 then
                return path_error(point_path .. ".range", "must be positive")
            end
        end
    end
    return true
end

local function validate_motion(motion, path)
    if motion == nil then
        return true
    end
    if type(motion) ~= "table" or not MOTION_KINDS[motion.kind] then
        return path_error(path, "kind must be bob, spin, pulse, sway, or chain_sway")
    end
    local valid, err = validate_vector(motion.axis, 3, path .. ".axis", true)
    if not valid then return nil, err end
    for _, field in ipairs({ "amplitude", "speed", "phase" }) do
        if motion[field] ~= nil and not finite(motion[field]) then
            return path_error(path .. "." .. field, "must be a finite number")
        end
    end
    if motion.kind == "sway" or motion.kind == "chain_sway" then
        valid, err = validate_vector(motion.secondary_axis, 3, path .. ".secondary_axis", true)
        if not valid then return nil, err end
        for _, field in ipairs({ "secondary_amplitude", "secondary_speed", "secondary_phase" }) do
            if motion[field] ~= nil and not finite(motion[field]) then
                return path_error(path .. "." .. field, "must be a finite number")
            end
        end
    end
    if motion.kind == "chain_sway" then
        if type(motion.terminal) ~= "string" or motion.terminal == "" then
            return path_error(path .. ".terminal", "must be a non-empty authored node name")
        end
        valid, err = validate_vector(motion.link_axis, 3, path .. ".link_axis", true)
        if not valid then return nil, err end
        for _, field in ipairs({ "link_amplitude", "link_phase_lag", "link_min_weight", "link_curve" }) do
            if motion[field] ~= nil and not finite(motion[field]) then
                return path_error(path .. "." .. field, "must be a finite number")
            end
        end
        if motion.link_min_weight ~= nil and (motion.link_min_weight < 0 or motion.link_min_weight > 1) then
            return path_error(path .. ".link_min_weight", "must be between 0 and 1")
        end
        if motion.link_curve ~= nil and motion.link_curve <= 0 then
            return path_error(path .. ".link_curve", "must be positive")
        end
    end
    return true
end

local function validate_authored_motions(specification)
    if specification.motions == nil then
        return true
    end
    local count, array_err = validate_dense_array(specification.motions, "authored_scene.motions")
    if not count then return nil, array_err end
    local required_nodes, nodes_err = validate_unique_name_array(
        specification.required_nodes,
        "authored_scene.required_nodes"
    )
    if not required_nodes then return nil, nodes_err end
    local animated_nodes = {}
    for index = 1, count do
        local motion = specification.motions[index]
        local path = "authored_scene.motions." .. tostring(index)
        if type(motion) ~= "table" then
            return path_error(path, "must be a motion table")
        end
        if type(motion.node) ~= "string" or motion.node == "" then
            return path_error(path .. ".node", "must be a non-empty authored node name")
        end
        if not required_nodes[motion.node] then
            return path_error(path .. ".node", "must reference authored_scene.required_nodes")
        end
        if animated_nodes[motion.node] then
            return path_error(path .. ".node", "must not animate the same node twice")
        end
        animated_nodes[motion.node] = true
        local valid, err = validate_motion(motion, path)
        if not valid then return nil, err end
        if motion.kind == "chain_sway" then
            if not required_nodes[motion.terminal] then
                return path_error(
                    path .. ".terminal",
                    "must reference authored_scene.required_nodes"
                )
            end
            if motion.terminal == motion.node then
                return path_error(path .. ".terminal", "must be distinct from the chain node")
            end
        end
    end
    return true
end

local function validate_output(output, path)
    if output == nil then
        return true
    end
    if type(output) ~= "table" then
        return path_error(path, "must be a table")
    end
    local valid, err = validate_vector(output.clear_color, 4, path .. ".clear_color", true)
    if not valid then return nil, err end
    if output.fog then
        valid, err = validate_vector(output.fog.color, 3, path .. ".fog.color", true)
        if not valid then return nil, err end
        if output.fog.strength ~= nil and not finite(output.fog.strength) then
            return path_error(path .. ".fog.strength", "must be a finite number")
        end
    end
    if output.bloom ~= nil and output.bloom ~= false then
        if type(output.bloom) ~= "table" then
            return path_error(path .. ".bloom", "must be a table or false")
        end
        for _, field in ipairs({ "threshold", "soft_knee", "strength", "radius", "scale" }) do
            if output.bloom[field] ~= nil and not finite(output.bloom[field]) then
                return path_error(path .. ".bloom." .. field, "must be a finite number")
            end
        end
        if output.bloom.scale ~= nil and (output.bloom.scale <= 0 or output.bloom.scale > 1) then
            return path_error(path .. ".bloom.scale", "must be greater than 0 and at most 1")
        end
        if output.bloom.tint ~= nil then
            valid, err = validate_vector(output.bloom.tint, 3, path .. ".bloom.tint", false)
            if not valid then return nil, err end
        end
    end
    for _, field in ipairs({ "x", "y", "width", "height", "output_width", "output_height", "vignette" }) do
        if output[field] ~= nil and not finite(output[field]) then
            return path_error(path .. "." .. field, "must be a finite number")
        end
    end
    if (output.width and output.width <= 0) or (output.height and output.height <= 0) then
        return path_error(path, "width and height must be positive")
    end
    return true
end

local function validate_camera_rig(rig, path)
    if rig == nil then
        return true
    end
    if type(rig) ~= "table" or (rig.kind ~= "map_follow" and rig.kind ~= "world_map") then
        return path_error(path, "kind must be map_follow")
    end
    if rig.map_plane ~= nil and not MAP_PLANES[rig.map_plane] then
        return path_error(path .. ".map_plane", "must be xy, xz, or yz")
    end
    local valid, err = validate_vector(rig.map_origin, 2, path .. ".map_origin", true)
    if not valid then return nil, err end
    valid, err = validate_vector(rig.world_origin, 3, path .. ".world_origin", true)
    if not valid then return nil, err end
    valid, err = validate_vector(rig.position_offset, 3, path .. ".position_offset", true)
    if not valid then return nil, err end
    valid, err = validate_vector(rig.target_offset, 3, path .. ".target_offset", true)
    if not valid then return nil, err end
    if rig.zoom_mode ~= nil and rig.zoom_mode ~= "none" and rig.zoom_mode ~= "fov" then
        return path_error(path .. ".zoom_mode", "must be none or fov")
    end
    for _, field in ipairs({ "map_scale", "zoom_reference", "zoom_factor", "base_fov", "min_fov", "max_fov" }) do
        if rig[field] ~= nil and not finite(rig[field]) then
            return path_error(path .. "." .. field, "must be a finite number")
        end
    end
    if rig.map_scale ~= nil and rig.map_scale == 0 then
        return path_error(path .. ".map_scale", "cannot be zero")
    end
    if rig.zoom_reference ~= nil and rig.zoom_reference <= 0 then
        return path_error(path .. ".zoom_reference", "must be positive")
    end
    for _, field in ipairs({ "base_fov", "min_fov", "max_fov" }) do
        if rig[field] and (rig[field] <= 0 or rig[field] >= math.pi) then
            return path_error(path .. "." .. field, "must be between 0 and pi radians")
        end
    end
    if rig.min_fov and rig.max_fov and rig.min_fov > rig.max_fov then
        return path_error(path, "min_fov cannot exceed max_fov")
    end
    return true
end

local function validate_camera_follow(follow, path)
    if follow == nil then
        return true
    end
    if type(follow) ~= "table" or follow.kind ~= "camera_x" then
        return path_error(path, "kind must be camera_x")
    end
    local valid, err = validate_vector(follow.position_offset, 3, path .. ".position_offset", true)
    if not valid then return nil, err end
    valid, err = validate_vector(follow.target_offset, 3, path .. ".target_offset", true)
    if not valid then return nil, err end
    for _, field in ipairs({ "reference_distance", "yaw", "smoothing" }) do
        if follow[field] ~= nil and not finite(follow[field]) then
            return path_error(path .. "." .. field, "must be a finite number")
        end
    end
    if follow.reference_distance ~= nil and follow.reference_distance <= 0 then
        return path_error(path .. ".reference_distance", "must be positive")
    end
    if follow.smoothing ~= nil and follow.smoothing < 0 then
        return path_error(path .. ".smoothing", "must be non-negative")
    end
    return true
end

--- Validates the numeric snapshot returned by captureWorldContext.
function Runtime.validateWorldContext(context)
    local plain, plain_err = validate_plain_value(context, "world context", {})
    if not plain then return nil, plain_err end
    if type(context) ~= "table" or type(context.camera) ~= "table" then
        return nil, "world context must contain a camera table"
    end
    local camera = context.camera
    for _, field in ipairs({ "x", "y", "zoom_x", "zoom_y", "rotation", "width", "height" }) do
        if not finite(camera[field]) then
            return nil, "world context camera." .. field .. " must be a finite number"
        end
    end
    if camera.zoom_x <= 0 or camera.zoom_y <= 0 then
        return nil, "world context camera zoom must be positive"
    end
    return true
end

local function call_number_pair(object, method)
    if type(object[method]) ~= "function" then
        return nil
    end
    local ok, first, second = pcall(object[method], object)
    if ok and finite(first) and finite(second) then
        return first, second
    end
    return nil
end

--- Captures only the numeric map-camera state required by a declarative rig.
function Runtime.captureWorldContext(world, options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, "world context options must be a table"
    end
    local camera = options.camera
    if camera == nil and type(world) == "table" then
        camera = world.camera or world
    end
    if type(camera) ~= "table" then
        return nil, "world context requires a world or camera with numeric camera fields"
    end
    local x, y
    if options.include_effects ~= false then
        x, y = call_number_pair(camera, "getOffsetPos")
    end
    if not x then
        x, y = call_number_pair(camera, "getPosition")
    end
    x = x or camera.x
    y = y or camera.y
    if not finite(x) or not finite(y) then
        return nil, "world camera must provide finite x and y values"
    end
    local zoom_x, zoom_y = call_number_pair(camera, "getZoom")
    zoom_x = zoom_x or camera.zoom_x or 1
    zoom_y = zoom_y or camera.zoom_y or zoom_x
    local rotation = camera.rotation or 0
    local width = camera.width or 0
    local height = camera.height or 0
    local valid, err = Runtime.validateWorldContext({
        camera = {
            x = x,
            y = y,
            zoom_x = zoom_x,
            zoom_y = zoom_y,
            rotation = rotation,
            width = width,
            height = height,
        },
    })
    if not valid then return nil, err end
    local context = {
        camera = {
            x = x,
            y = y,
            zoom_x = zoom_x,
            zoom_y = zoom_y,
            rotation = rotation,
            width = width,
            height = height,
        },
    }
    if type(world) == "table" then
        context.map = {
            width = finite(world.width) and world.width or 0,
            height = finite(world.height) and world.height or 0,
        }
    end
    return context
end

--- Validates the supported data-only runtime definition.
---@return boolean? valid
---@return string? err
function Runtime.validateDefinition(definition)
    if type(definition) ~= "table" then
        return nil, "definition must be a table"
    end
    local plain, plain_err = validate_plain_value(definition, "definition", {})
    if not plain then return nil, plain_err end
    local authored_scene = definition.authored_scene ~= nil
    if definition.version ~= nil and definition.version ~= 1 and definition.version ~= 2 then
        return nil, "definition.version must be 1 or 2"
    end
    if authored_scene and definition.version ~= 2 then
        return nil, "authored_scene definitions must use version 2"
    end
    if not authored_scene and definition.version == 2 then
        return nil, "definition.version 2 requires authored_scene"
    end
    -- The declarative path intentionally cannot replace library-owned shaders
    -- or renderer setup. Use the direct API only when writing another library.
    if definition.renderer ~= nil then
        return nil, "definition.renderer is unsupported by the declarative runtime"
    end
    if authored_scene then
        if definition.assets ~= nil then
            return nil, "authored_scene definitions may not define assets"
        end
    else
        if type(definition.assets) ~= "table" then
            return nil, "definition.assets must be a table keyed by asset id"
        end
        for id, asset in pairs(definition.assets) do
            if type(id) ~= "string" or id == "" then
                return nil, "asset ids must be non-empty strings"
            end
            if type(asset) ~= "table" or type(asset.path) ~= "string" or asset.path == "" then
                return nil, "assets." .. id .. " must define a non-empty path"
            end
            if asset.coordinate_space ~= nil
                and asset.coordinate_space ~= "gltf_y_up"
                and asset.coordinate_space ~= "blender_z_up"
            then
                return nil, "assets." .. id .. ".coordinate_space must be gltf_y_up or blender_z_up"
            end
            if asset.material_overrides then
                if type(asset.material_overrides) ~= "table" then
                    return nil, "assets." .. id .. ".material_overrides must be a table"
                end
                for source_name, material in pairs(asset.material_overrides) do
                    if type(source_name) ~= "string" and type(source_name) ~= "number" then
                        return nil, "assets." .. id .. ".material_overrides has an invalid material key"
                    end
                    if type(material) ~= "string" then
                        local valid, err = validate_material_spec(material, "assets." .. id .. ".material_overrides." .. tostring(source_name))
                        if not valid then return nil, err end
                    end
                end
            end
        end
    end
    if definition.materials then
        if type(definition.materials) ~= "table" then
            return nil, "definition.materials must be a table keyed by material id"
        end
        for id, material in pairs(definition.materials) do
            if type(id) ~= "string" or id == "" then
                return nil, "material ids must be non-empty strings"
            end
            local valid, err = validate_material_spec(material, "materials." .. id)
            if not valid then return nil, err end
        end
    end
    if authored_scene then
        local authored_valid, authored_err = validate_authored_scene(definition.authored_scene, definition.materials)
        if not authored_valid then return nil, authored_err end
        local authored_motions_valid, authored_motions_err = validate_authored_motions(definition.authored_scene)
        if not authored_motions_valid then return nil, authored_motions_err end
    else
        for asset_id, asset in pairs(definition.assets) do
            for source_name, material in pairs(asset.material_overrides or {}) do
                if type(material) == "string" and (not definition.materials or not definition.materials[material]) then
                    return nil, "assets." .. asset_id .. ".material_overrides." .. tostring(source_name) .. " references unknown material " .. material
                end
            end
        end
    end
    if definition.scene then
        if type(definition.scene) ~= "table" then
            return nil, "definition.scene must be a table"
        end
        local valid, err = validate_vector(definition.scene.clear_color, 4, "scene.clear_color", true)
        if not valid then return nil, err end
        if definition.scene.light then
            valid, err = validate_vector(definition.scene.light.direction, 3, "scene.light.direction", true)
            if not valid then return nil, err end
            valid, err = validate_vector(definition.scene.light.color, 3, "scene.light.color", true)
            if not valid then return nil, err end
            valid, err = validate_vector(definition.scene.light.ambient, 3, "scene.light.ambient", true)
            if not valid then return nil, err end
            if definition.scene.light.fill ~= nil then
                if type(definition.scene.light.fill) ~= "table" then
                    return nil, "scene.light.fill must be a table"
                end
                valid, err = validate_vector(
                    definition.scene.light.fill.direction,
                    3,
                    "scene.light.fill.direction",
                    true
                )
                if not valid then return nil, err end
                valid, err = validate_vector(
                    definition.scene.light.fill.color,
                    3,
                    "scene.light.fill.color",
                    true
                )
                if not valid then return nil, err end
                if definition.scene.light.fill.strength ~= nil and not finite(definition.scene.light.fill.strength) then
                    return nil, "scene.light.fill.strength must be a finite number"
                end
            end
            if definition.scene.light.point_lights ~= nil then
                local point_count, point_err = validate_dense_array(
                    definition.scene.light.point_lights,
                    "scene.light.point_lights"
                )
                if not point_count then return nil, point_err end
                if point_count > 4 then
                    return nil, "scene.light.point_lights supports at most four lights"
                end
                for index = 1, point_count do
                    local point = definition.scene.light.point_lights[index]
                    if type(point) ~= "table" then
                        return nil, "scene.light.point_lights." .. tostring(index) .. " must be a table"
                    end
                    valid, err = validate_vector(point.position, 3, "scene.light.point_lights." .. tostring(index) .. ".position", false)
                    if not valid then return nil, err end
                    valid, err = validate_vector(point.color, 3, "scene.light.point_lights." .. tostring(index) .. ".color", false)
                    if not valid then return nil, err end
                    for _, field in ipairs({ "strength", "range" }) do
                        if point[field] == nil or not finite(point[field]) or point[field] < 0 then
                            return nil, "scene.light.point_lights." .. tostring(index) .. "." .. field .. " must be a non-negative number"
                        end
                    end
                    if point.range <= 0 then
                        return nil, "scene.light.point_lights." .. tostring(index) .. ".range must be positive"
                    end
                end
            end
        end
        if definition.scene.camera then
            valid, err = validate_vector(definition.scene.camera.position, 3, "scene.camera.position", true)
            if not valid then return nil, err end
            valid, err = validate_vector(definition.scene.camera.target, 3, "scene.camera.target", true)
            if not valid then return nil, err end
            valid, err = validate_vector(definition.scene.camera.up, 3, "scene.camera.up", true)
            if not valid then return nil, err end
            for _, field in ipairs({ "fov", "near", "far" }) do
                if definition.scene.camera[field] ~= nil and not finite(definition.scene.camera[field]) then
                    return nil, "scene.camera." .. field .. " must be a finite number"
                end
            end
            local camera = definition.scene.camera
            if camera.fov and (camera.fov <= 0 or camera.fov >= math.pi) then
                return nil, "scene.camera.fov must be between 0 and pi radians"
            end
            if camera.near and camera.near <= 0 then
                return nil, "scene.camera.near must be positive"
            end
            if camera.far and camera.near and camera.far <= camera.near then
                return nil, "scene.camera.far must be greater than near"
            end
        end
    end
    if authored_scene and definition.scene and definition.scene.camera then
        return nil, "authored_scene camera position and target must come from Blender anchors"
    end
    if authored_scene and definition.camera_motion then
        return nil, "authored_scene may not define camera_motion"
    end
    if authored_scene and definition.camera_rig then
        return nil, "authored_scene may not define camera_rig"
    end
    if definition.camera_follow and not authored_scene then
        return nil, "camera_follow requires authored_scene camera anchors"
    end
    local camera_follow_valid, camera_follow_err = validate_camera_follow(
        definition.camera_follow,
        "camera_follow"
    )
    if not camera_follow_valid then return nil, camera_follow_err end
    if authored_scene and definition.instances ~= nil then
        return nil, "authored_scene may not define instances"
    end
    if definition.camera_motion then
        local motion = definition.camera_motion
        if type(motion) ~= "table" or motion.kind ~= "orbit" then
            return nil, "camera_motion.kind must be orbit"
        end
        local valid, err = validate_vector(motion.center, 3, "camera_motion.center", true)
        if not valid then return nil, err end
        valid, err = validate_vector(motion.target, 3, "camera_motion.target", true)
        if not valid then return nil, err end
        for _, field in ipairs({ "radius", "height", "speed", "phase" }) do
            if motion[field] ~= nil and not finite(motion[field]) then
                return nil, "camera_motion." .. field .. " must be a finite number"
            end
        end
    end
    if definition.camera_motion and definition.camera_rig then
        return nil, "camera_motion and camera_rig cannot be combined"
    end
    local rig_valid, rig_err = validate_camera_rig(definition.camera_rig, "camera_rig")
    if not rig_valid then return nil, rig_err end
    local instance_count = 0
    if definition.instances ~= nil then
        local count, array_err = validate_dense_array(definition.instances, "definition.instances")
        if not count then return nil, array_err end
        instance_count = count
    end
    local instance_ids = {}
    for index = 1, instance_count do
        local instance = definition.instances[index]
        if type(instance) ~= "table" or type(instance.asset) ~= "string" then
            return nil, "instances." .. tostring(index) .. " must define an asset id"
        end
        if not definition.assets[instance.asset] then
            return nil, "instances." .. tostring(index) .. " references unknown asset " .. instance.asset
        end
        if instance.id ~= nil then
            if type(instance.id) ~= "string" or instance.id == "" then
                return nil, "instances." .. tostring(index) .. ".id must be a non-empty string"
            end
            if instance_ids[instance.id] then
                return nil, "instances." .. tostring(index) .. ".id duplicates " .. instance.id
            end
            instance_ids[instance.id] = true
        end
        if instance.node ~= nil and type(instance.node) ~= "string" and type(instance.node) ~= "number" then
            return nil, "instances." .. tostring(index) .. ".node must be a node name or index"
        end
        local valid, err = validate_transform(instance.transform, "instances." .. tostring(index) .. ".transform")
        if not valid then return nil, err end
        valid, err = validate_motion(instance.motion, "instances." .. tostring(index) .. ".motion")
        if not valid then return nil, err end
        if instance.motion and instance.motion.kind == "chain_sway" then
            return nil, "instances." .. tostring(index) .. ".motion.chain_sway requires authored_scene"
        end
        if instance.material ~= nil then
            if type(instance.material) ~= "string" then
                valid, err = validate_material_spec(instance.material, "instances." .. tostring(index) .. ".material")
                if not valid then return nil, err end
            elseif not definition.materials or not definition.materials[instance.material] then
                return nil, "instances." .. tostring(index) .. " references unknown material " .. instance.material
            end
        end
    end
    local valid, err = validate_output(definition.output, "output")
    if not valid then return nil, err end
    return true
end

local function copy_material_data(material)
    return {
        name = material.name,
        shader = material.shader,
        base_color = material.base_color,
        emissive = material.emissive,
        metallic = material.metallic,
        roughness = material.roughness,
        specular_strength = material.specular_strength,
        ambient_reflection = material.ambient_reflection,
        normal_strength = material.normal_strength,
        uv_scale = material.uv_scale,
        alpha_mode = material.alpha_mode,
        alpha_cutoff = material.alpha_cutoff,
        double_sided = material.double_sided,
        base_color_texture = material.base_color_texture,
        normal_texture = material.normal_texture,
        roughness_texture = material.roughness_texture,
    }
end

local function resolve_path(path, root)
    if not root or root == "" or path:sub(1, 1) == "/" then
        return path
    end
    if root:sub(-1) == "/" then
        return root .. path
    end
    return root .. "/" .. path
end

local function resolve_material_paths(material, root)
    return Material.resolveTexturePaths(material, function(path)
        return resolve_path(path, root)
    end)
end

local function ordered_keys(table_value)
    local keys = {}
    for key in pairs(table_value or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function transform_values(instance)
    return instance.transform or {}
end

local function instance_material(runtime, specification)
    if specification == nil then
        return nil
    end
    if type(specification) == "string" then
        return runtime.materials[specification]
    end
    local options, resolve_err = resolve_material_paths(specification, runtime.context.asset_root)
    if not options then
        return nil, resolve_err
    end
    local material, err = Material.new(options)
    if not material then
        return nil, err
    end
    runtime.owned_materials[#runtime.owned_materials + 1] = material
    return material
end

local function compile_asset_overrides(asset, materials, asset_root)
    if not asset.material_overrides then
        return nil
    end
    local overrides = {}
    for source_name, override in pairs(asset.material_overrides) do
        if type(override) == "string" then
            overrides[source_name] = copy_material_data(materials[override])
        else
            local resolved, resolve_err = resolve_material_paths(override, asset_root)
            if not resolved then
                return nil, resolve_err
            end
            overrides[source_name] = resolved
        end
    end
    return overrides
end

local function is_descendant_of(node, ancestor)
    local current = node
    while current do
        if current == ancestor then
            return true
        end
        current = current.parent
    end
    return false
end

local function require_authored_source_nodes(model, specification)
    local root, root_err = model:requireUniqueNode(specification.root)
    if not root then return nil, root_err end
    for _, name in ipairs(specification.required_nodes) do
        local node, node_err = model:requireUniqueNode(name)
        if not node then return nil, node_err end
        if not is_descendant_of(node, root) then
            return nil, "authored node " .. name .. " is not a descendant of " .. specification.root
        end
    end
    for source_name in pairs(specification.material_overrides or {}) do
        local material_ok, material_err = model:requireUniqueMaterial(source_name)
        if not material_ok then return nil, material_err end
    end
    return root
end

local function authored_camera_options(specification)
    local camera = specification.camera
    return {
        fov = camera.fov,
        near = camera.near,
        far = camera.far,
    }
end

local function node_world_position(node)
    return Math3D.transformPoint(node.world_matrix, { 0, 0, 0 })
end

local function collect_authored_chain_links(node, output)
    for _, child in ipairs(node.children) do
        if child.user_data and child.user_data.ddd_role == "chain_link" then
            output[#output + 1] = child
        else
            collect_authored_chain_links(child, output)
        end
    end
end

local function ordered_authored_chain_links(node, node_name)
    local links = {}
    collect_authored_chain_links(node, links)
    if #links == 0 then
        return nil, "chain_sway node " .. tostring(node_name) .. " has no ddd_role=chain_link descendants"
    end
    for _, link in ipairs(links) do
        local authored_index = link.user_data.ddd_link_index
        if not finite(authored_index) or authored_index < 0 or authored_index % 1 ~= 0 then
            return nil, "chain_sway link " .. tostring(link.name) .. " has an invalid ddd_link_index"
        end
    end
    table.sort(links, function(left, right)
        return left.user_data.ddd_link_index < right.user_data.ddd_link_index
    end)
    for index, link in ipairs(links) do
        local authored_index = link.user_data.ddd_link_index
        if authored_index ~= index - 1 then
            return nil, "chain_sway links below " .. tostring(node_name) .. " must use dense ddd_link_index values"
        end
    end
    return links
end

local function add_motion(runtime, node, specification, authored_nodes)
    local motion = specification.motion or specification
    if not motion.kind then return true end
    local entry = {
        node = node,
        kind = motion.kind,
        axis = Math3D.normalize3(motion.axis or { 0, 1, 0 }, { 0, 1, 0 }),
        amplitude = motion.amplitude or 0,
        speed = motion.speed or 0,
        phase = motion.phase or 0,
        secondary_axis = motion.secondary_axis
            and Math3D.normalize3(motion.secondary_axis, { 0, 0, 1 })
            or nil,
        secondary_amplitude = motion.secondary_amplitude or 0,
        secondary_speed = motion.secondary_speed or 0,
        secondary_phase = motion.secondary_phase or 0,
        position = Math3D.copy3(node.position),
        rotation = Math3D.copyQuat(node.rotation),
        scale = Math3D.copy3(node.scale, { 1, 1, 1 }),
    }
    if motion.kind == "chain_sway" then
        local terminal = authored_nodes and authored_nodes[motion.terminal]
        if not terminal then
            return nil, "chain_sway terminal is unavailable: " .. tostring(motion.terminal)
        end
        local links, links_err = ordered_authored_chain_links(node, specification.node)
        if not links then return nil, links_err end
        entry.terminal = terminal
        entry.terminal_rotation = Math3D.copyQuat(terminal.rotation)
        entry.link_axis = Math3D.normalize3(motion.link_axis or motion.axis or { 0, 1, 0 }, { 0, 1, 0 })
        entry.link_amplitude = motion.link_amplitude == nil and entry.amplitude or motion.link_amplitude
        entry.link_phase_lag = motion.link_phase_lag or 0
        entry.link_min_weight = motion.link_min_weight or 0
        entry.link_curve = motion.link_curve or 1
        entry.links = {}
        for _, link in ipairs(links) do
            entry.links[#entry.links + 1] = {
                node = link,
                rotation = Math3D.copyQuat(link.rotation),
            }
        end
    end
    runtime.motions[#runtime.motions + 1] = entry
    return true
end

local function copy_vec2(value, fallback)
    value = value or fallback
    return { value[1] or 0, value[2] or 0 }
end

local function make_camera_rig(specification, camera)
    if not specification then
        return nil
    end
    return {
        map_plane = specification.map_plane or "xz",
        map_origin = copy_vec2(specification.map_origin, { 0, 0 }),
        world_origin = Math3D.copy3(specification.world_origin, { 0, 0, 0 }),
        position_offset = Math3D.copy3(specification.position_offset, { 0, 8, 12 }),
        target_offset = Math3D.copy3(specification.target_offset, { 0, 0, 0 }),
        map_scale = specification.map_scale or 1,
        zoom_mode = specification.zoom_mode or "none",
        zoom_reference = specification.zoom_reference or 1,
        zoom_factor = specification.zoom_factor == nil and 1 or specification.zoom_factor,
        base_fov = specification.base_fov or camera.fov,
        min_fov = specification.min_fov or math.rad(15),
        max_fov = specification.max_fov or math.rad(100),
    }
end

local function make_camera_follow(specification)
    if not specification then
        return nil
    end
    return {
        reference_distance = specification.reference_distance or 160,
        position_offset = Math3D.copy3(specification.position_offset, { 0.24, 0, 0 }),
        target_offset = Math3D.copy3(specification.target_offset, { 0.10, 0, 0 }),
        yaw = specification.yaw or 0,
        smoothing = specification.smoothing == nil and 7 or specification.smoothing,
        reference_x = nil,
        influence = 0,
    }
end

local function rotate_around_y(point, pivot, angle)
    local cosine = math.cos(angle)
    local sine = math.sin(angle)
    local x = point[1] - pivot[1]
    local z = point[3] - pivot[3]
    return {
        pivot[1] + cosine * x + sine * z,
        point[2],
        pivot[3] - sine * x + cosine * z,
    }
end

local function map_camera_point(rig, camera)
    local point = Math3D.copy3(rig.world_origin)
    local axes = MAP_PLANES[rig.map_plane]
    point[axes[1]] = point[axes[1]] + (camera.x - rig.map_origin[1]) * rig.map_scale
    point[axes[2]] = point[axes[2]] + (camera.y - rig.map_origin[2]) * rig.map_scale
    return point
end

function Runtime:_applyCameraRig(world_context)
    if not self.camera_rig or not world_context then
        return true
    end
    local camera_context = world_context.camera
    local anchor = map_camera_point(self.camera_rig, camera_context)
    self.scene.camera:setPosition(Math3D.add3(anchor, self.camera_rig.position_offset))
    local looked_at, look_err = self.scene.camera:lookAt(Math3D.add3(anchor, self.camera_rig.target_offset))
    if not looked_at then return nil, look_err end
    if self.camera_rig.zoom_mode == "fov" then
        local zoom = (camera_context.zoom_x + camera_context.zoom_y) * 0.5
        local fov = self.camera_rig.base_fov / ((zoom / self.camera_rig.zoom_reference) ^ self.camera_rig.zoom_factor)
        fov = math.max(self.camera_rig.min_fov, math.min(self.camera_rig.max_fov, fov))
        local set, set_err = self.scene.camera:setFovRadians(fov)
        if not set then return nil, set_err end
    end
    return true
end

function Runtime:_applyAuthoredLights()
    if not self.authored_point_lights then
        return true
    end
    local points = {}
    for index, specification in ipairs(self.authored_point_lights) do
        local node = self.nodes[specification.node]
        if not node then
            return nil, "authored point light node is unavailable: " .. tostring(specification.node)
        end
        points[index] = {
            position = node_world_position(node),
            color = deep_copy(specification.color),
            strength = specification.strength,
            range = specification.range,
        }
    end
    return self.scene:setLight({ point_lights = points })
end

function Runtime:_applyAuthoredCamera()
    local authored_scene = self.authored_scene
    if not authored_scene then
        return true
    end
    self.scene.root:updateWorldMatrix()
    local position = node_world_position(authored_scene.camera_anchor)
    local target = node_world_position(authored_scene.camera_target)
    self.authored_camera_position = Math3D.copy3(position)
    self.authored_camera_target = Math3D.copy3(target)
    self.scene.camera:setPosition(position)
    local looked_at, look_err = self.scene.camera:lookAt(target)
    if not looked_at then
        return nil, look_err
    end
    return true
end

function Runtime:_applyCameraFollow(world_context)
    local follow = self.camera_follow
    local camera = world_context and world_context.camera
    if not follow or not camera or not self.authored_camera_position or not self.authored_camera_target then
        return true
    end

    if follow.reference_x == nil then
        return true
    end

    local desired = (camera.x - follow.reference_x) / follow.reference_distance
    if follow.smoothing <= 0 or self.last_dt <= 0 then
        follow.influence = desired
    else
        local amount = 1 - math.exp(-follow.smoothing * self.last_dt)
        follow.influence = follow.influence + (desired - follow.influence) * amount
    end

    local position = rotate_around_y(
        self.authored_camera_position,
        self.authored_camera_target,
        follow.yaw * follow.influence
    )
    position = Math3D.add3(position, Math3D.scale3(follow.position_offset, follow.influence))
    local target = Math3D.add3(
        self.authored_camera_target,
        Math3D.scale3(follow.target_offset, follow.influence)
    )
    self.scene.camera:setPosition(position)
    local looked_at, look_err = self.scene.camera:lookAt(target)
    if not looked_at then return nil, look_err end
    return true
end

local function oscillating_rotation(time, base_rotation, motion, value)
    local rotation = Math3D.multiplyQuat(
        base_rotation,
        Math3D.quatFromAxisAngle(motion.axis, motion.amplitude * value)
    )
    if motion.secondary_axis then
        local secondary_value = math.sin(time * motion.secondary_speed + motion.secondary_phase)
        rotation = Math3D.multiplyQuat(
            rotation,
            Math3D.quatFromAxisAngle(
                motion.secondary_axis,
                motion.secondary_amplitude * secondary_value
            )
        )
    end
    return rotation
end

function Runtime:_applyMotions(world_context)
    for _, motion in ipairs(self.motions) do
        local value = math.sin(self.time * motion.speed + motion.phase)
        if motion.kind == "bob" then
            motion.node:setPosition(Math3D.add3(motion.position, Math3D.scale3(motion.axis, motion.amplitude * value)))
        elseif motion.kind == "spin" then
            local rotation = Math3D.quatFromAxisAngle(motion.axis, self.time * motion.speed + motion.phase)
            motion.node:setRotation(Math3D.multiplyQuat(motion.rotation, rotation))
        elseif motion.kind == "pulse" then
            local scale = 1 + motion.amplitude * value
            motion.node:setScale(motion.scale[1] * scale, motion.scale[2] * scale, motion.scale[3] * scale)
        elseif motion.kind == "sway" then
            motion.node:setRotation(oscillating_rotation(self.time, motion.rotation, motion, value))
        elseif motion.kind == "chain_sway" then
            motion.terminal:setRotation(oscillating_rotation(self.time, motion.terminal_rotation, motion, value))
            local link_count = #motion.links
            for index, link in ipairs(motion.links) do
                local progress = link_count == 1 and 1 or (index - 1) / (link_count - 1)
                local weight = motion.link_min_weight
                    + (1 - motion.link_min_weight) * progress ^ motion.link_curve
                local link_value = math.sin(
                    self.time * motion.speed + motion.phase - (1 - progress) * motion.link_phase_lag
                )
                link.node:setRotation(Math3D.multiplyQuat(
                    link.rotation,
                    Math3D.quatFromAxisAngle(
                        motion.link_axis,
                        motion.link_amplitude * weight * link_value
                    )
                ))
            end
        end
    end
    local camera_motion = self.camera_motion
    if camera_motion then
        local angle = self.time * camera_motion.speed + camera_motion.phase
        local position = {
            camera_motion.center[1] + math.cos(angle) * camera_motion.radius,
            camera_motion.center[2] + camera_motion.height,
            camera_motion.center[3] + math.sin(angle) * camera_motion.radius,
        }
        self.scene.camera:setPosition(position)
        self.scene.camera:lookAt(camera_motion.target)
    end
    local authored_ok, authored_err = self:_applyAuthoredCamera()
    if not authored_ok then return nil, authored_err end
    local follow_ok, follow_err = self:_applyCameraFollow(world_context)
    if not follow_ok then return nil, follow_err end
    return self:_applyCameraRig(world_context)
end

local function merge_output(base, override)
    local output = {}
    for key, value in pairs(base or {}) do
        output[key] = value
    end
    for key, value in pairs(override or {}) do
        output[key] = value
    end
    if base and base.fog or override and override.fog then
        output.fog = {}
        for key, value in pairs((base and base.fog) or {}) do output.fog[key] = value end
        for key, value in pairs((override and override.fog) or {}) do output.fog[key] = value end
    end
    return output
end

function Runtime.new(definition, context)
    local valid, validation_err = Runtime.validateDefinition(definition)
    if not valid then
        return nil, validation_err
    end
    -- Keep preset modules safely cacheable: runtime never retains caller tables.
    definition = deep_copy(definition)
    context = context or {}
    if type(context) ~= "table" then
        return nil, "runtime context must be a table"
    end
    if context.asset_root ~= nil and type(context.asset_root) ~= "string" then
        return nil, "runtime context asset_root must be a string"
    end
    local context_output_valid, context_output_err = validate_output(context.output, "context.output")
    if not context_output_valid then
        return nil, context_output_err
    end
    local runtime_context = {
        asset_root = context.asset_root,
        output = deep_copy(context.output or {}),
    }
    local authored_specification = definition.authored_scene
    local scene_definition = definition.scene or {}
    local scene, scene_err = Scene.new({
        camera = authored_specification and authored_camera_options(authored_specification) or scene_definition.camera,
        clear_color = scene_definition.clear_color,
        light = scene_definition.light,
        width = scene_definition.width,
        height = scene_definition.height,
    })
    if not scene then
        return nil, scene_err
    end
    local runtime = setmetatable({
        definition = definition,
        context = runtime_context,
        scene = scene,
        materials = {},
        models = {},
        nodes = {},
        motions = {},
        owned_materials = {},
        time = 0,
        last_dt = 0,
        output = merge_output(definition.output, runtime_context.output),
        released = false,
    }, Runtime)

    local function abort(message)
        runtime:release()
        return nil, message
    end

    for _, material_id in ipairs(ordered_keys(definition.materials)) do
        local material_specification = deep_copy(definition.materials[material_id])
        material_specification.name = material_specification.name or material_id
        local material_options, texture_err = resolve_material_paths(material_specification, runtime_context.asset_root)
        if not material_options then
            return abort("material " .. material_id .. ": " .. tostring(texture_err))
        end
        local material, material_err = Material.new(material_options)
        if not material then
            return abort("material " .. material_id .. ": " .. tostring(material_err))
        end
        runtime.materials[material_id] = material
        runtime.owned_materials[#runtime.owned_materials + 1] = material
    end
    if authored_specification then
        local authored_overrides, authored_overrides_err = compile_asset_overrides({
            material_overrides = authored_specification.material_overrides,
        }, runtime.materials, runtime_context.asset_root)
        if authored_overrides_err then
            return abort("authored_scene: " .. tostring(authored_overrides_err))
        end
        local model, model_err = GLBLoader.load(
            resolve_path(authored_specification.path, runtime_context.asset_root),
            {
                source = authored_specification.path,
                material_overrides = authored_overrides,
                coordinate_space = authored_specification.coordinate_space,
            }
        )
        if not model then
            return abort("authored_scene: " .. tostring(model_err))
        end
        runtime.models.authored_scene = model
        local source_root, source_err = require_authored_source_nodes(model, authored_specification)
        if not source_root then
            return abort("authored_scene: " .. tostring(source_err))
        end
        local node, spawn_err = scene:spawn(model, { node = authored_specification.root })
        if not node then
            return abort("authored_scene: " .. tostring(spawn_err))
        end
        local cloned_nodes = {}
        for _, name in ipairs(authored_specification.required_nodes) do
            local cloned = node:find(name)
            if not cloned then
                return abort("authored_scene clone is missing node " .. name)
            end
            cloned_nodes[name] = cloned
            runtime.nodes[name] = cloned
        end
        runtime.authored_scene = {
            root = node,
            camera_anchor = cloned_nodes[authored_specification.camera.anchor],
            camera_target = cloned_nodes[authored_specification.camera.target_anchor],
        }
        runtime.authored_point_lights = deep_copy(authored_specification.point_lights)
        for _, specification in ipairs(authored_specification.motions or {}) do
            local motion_ok, motion_err = add_motion(
                runtime,
                cloned_nodes[specification.node],
                specification,
                cloned_nodes
            )
            if not motion_ok then
                return abort("authored_scene: " .. tostring(motion_err))
            end
        end
    else
        for _, asset_id in ipairs(ordered_keys(definition.assets)) do
            local asset = definition.assets[asset_id]
            local material_overrides, overrides_err = compile_asset_overrides(
                asset,
                runtime.materials,
                runtime_context.asset_root
            )
            if overrides_err then
                return abort("asset " .. asset_id .. ": " .. tostring(overrides_err))
            end
            local model, model_err = GLBLoader.load(resolve_path(asset.path, runtime_context.asset_root), {
                source = asset.path,
                mesh_usage = asset.mesh_usage,
                material_overrides = material_overrides,
                coordinate_space = asset.coordinate_space,
            })
            if not model then
                return abort("asset " .. asset_id .. ": " .. tostring(model_err))
            end
            runtime.models[asset_id] = model
        end
        for index, specification in ipairs(definition.instances or {}) do
            local material, material_err = instance_material(runtime, specification.material)
            if specification.material and not material then
                return abort("instance " .. tostring(index) .. ": " .. tostring(material_err))
            end
            local transform = transform_values(specification)
            local node, spawn_err = scene:spawn(runtime.models[specification.asset], {
                node = specification.node,
                name = specification.id,
                position = transform.position,
                rotation = transform.rotation,
                scale = transform.scale,
                matrix = transform.matrix,
                material = material,
                visible = specification.visible,
                enabled = specification.enabled,
            })
            if not node then
                return abort("instance " .. tostring(index) .. ": " .. tostring(spawn_err))
            end
            if specification.id then
                runtime.nodes[specification.id] = node
            end
            local motion_ok, motion_err = add_motion(runtime, node, specification)
            if not motion_ok then
                return abort("instance " .. tostring(index) .. ": " .. tostring(motion_err))
            end
        end
    end
    if definition.camera_motion then
        local motion = definition.camera_motion
        runtime.camera_motion = {
            center = Math3D.copy3(motion.center, { 0, 0, 0 }),
            target = Math3D.copy3(motion.target, { 0, 0, 0 }),
            radius = motion.radius or 0,
            height = motion.height or 0,
            speed = motion.speed or 0,
            phase = motion.phase or 0,
        }
    end
    runtime.camera_follow = make_camera_follow(definition.camera_follow)
    runtime.camera_rig = make_camera_rig(definition.camera_rig, scene.camera)
    local updated, update_err = runtime:update(0)
    if not updated then
        return abort(update_err)
    end
    return runtime
end

function Runtime:getNode(id)
    return self.nodes[id]
end

function Runtime:setCameraFollowOrigin(camera_x)
    if self.released then
        return nil, "runtime has been released"
    end
    if not finite(camera_x) then
        return nil, "camera follow origin must be a finite number"
    end
    if self.camera_follow then
        self.camera_follow.reference_x = camera_x
        self.camera_follow.influence = 0
    end
    return true
end

function Runtime:update(dt, world_context)
    if self.released then
        return nil, "runtime has been released"
    end
    dt = tonumber(dt)
    if not dt or dt < 0 then
        return nil, "runtime delta must be a non-negative number"
    end
    if world_context ~= nil then
        local context_valid, context_err = Runtime.validateWorldContext(world_context)
        if not context_valid then
            return nil, context_err
        end
        self.world_context = deep_copy(world_context)
    end
    self.time = self.time + dt
    self.last_dt = dt
    local applied, apply_err = self:_applyMotions(self.world_context)
    if not applied then
        return nil, apply_err
    end
    local updated, scene_err = self.scene:update(dt)
    if not updated then
        return nil, scene_err
    end
    local lights_applied, lights_err = self:_applyAuthoredLights()
    if not lights_applied then
        return nil, lights_err
    end
    return true
end

function Runtime:draw(options)
    if self.released then
        return nil, "runtime has been released"
    end
    if options ~= nil then
        local valid, err = validate_output(options, "draw")
        if not valid then return nil, err end
    end
    return self.scene:draw(merge_output(self.output, options))
end

function Runtime:release()
    if self.released then
        return true
    end
    local first_err
    if self.scene then
        local ok, err = self.scene:release()
        if not ok then first_err = err end
    end
    for _, model in pairs(self.models or {}) do
        local ok, err = model:release()
        if not ok and not first_err then first_err = err end
    end
    for _, material in ipairs(self.owned_materials or {}) do
        local ok, err = material:release()
        if not ok and not first_err then first_err = err end
    end
    self.models = {}
    self.materials = {}
    self.nodes = {}
    self.motions = {}
    self.owned_materials = {}
    self.world_context = nil
    self.authored_scene = nil
    self.released = true
    if first_err then return nil, first_err end
    return true
end

return Runtime
