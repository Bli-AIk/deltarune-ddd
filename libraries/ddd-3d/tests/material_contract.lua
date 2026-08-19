local source = debug.getinfo(1, "S").source:sub(2)
local library_root = source:match("^(.*)/tests/[^/]+$")
assert(library_root, "could not resolve ddd-3d library root")

local loaded = {}
function libRequire(id, path)
    assert(id == "ddd-3d", "unexpected library id: " .. tostring(id))
    local key = id .. ":" .. path
    if loaded[key] then
        return loaded[key]
    end
    local chunk, err = loadfile(library_root .. "/" .. path:gsub("%.", "/") .. ".lua")
    assert(chunk, err)
    loaded[key] = chunk()
    return loaded[key]
end

love = {
    filesystem = {},
    graphics = {
        isActive = function()
            return true
        end,
        newMesh = function()
            return {
                release = function() end,
            }
        end,
    },
}

local fixture_has_duplicate_material = false

local function fixture_document()
    local fill_name = fixture_has_duplicate_material and "suit_outline_metal" or "suit_fill_black"
    return {
        asset = { version = "2.0" },
        buffers = {
            { byteLength = 72 },
        },
        bufferViews = {
            { buffer = 0, byteOffset = 0, byteLength = 36 },
            { buffer = 0, byteOffset = 36, byteLength = 36 },
        },
        accessors = {
            { bufferView = 0, componentType = 5126, count = 3, type = "VEC3" },
            { bufferView = 1, componentType = 5126, count = 3, type = "VEC3" },
        },
        materials = {
            { name = "suit_outline_metal" },
            { name = fill_name },
        },
        meshes = {
            {
                primitives = {
                    { attributes = { POSITION = 0, NORMAL = 1 }, material = 0 },
                    { attributes = { POSITION = 0, NORMAL = 1 }, material = 1 },
                },
            },
        },
        nodes = {
            { name = "DDD_SCENE_ROOT", children = { 1, 2, 3 } },
            { name = "anchor_camera", translation = { 0, 0, 2 } },
            { name = "anchor_camera_target", translation = { 0, 0, 0 } },
            { name = "swing_pivot", children = { 4, 5 } },
            { name = "suits", mesh = 0, translation = { 0, -3, 0 } },
            { name = "chain", children = { 6, 7 } },
            {
                name = "chain_link_00",
                mesh = 0,
                translation = { 0, -1, 0 },
                extras = { ddd_role = "chain_link", ddd_link_index = 0 },
            },
            {
                name = "chain_link_01",
                mesh = 0,
                translation = { 0, -2, 0 },
                extras = { ddd_role = "chain_link", ddd_link_index = 1 },
            },
        },
        scenes = {
            { nodes = { 0 } },
        },
        scene = 0,
    }
end

JSON = {
    decode = function()
        return fixture_document()
    end,
}

local function u32(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

local function fixture_glb()
    local json = "{}  "
    local binary = string.rep("\0", 72)
    local total_length = 12 + 8 + #json + 8 + #binary
    return "glTF"
        .. u32(2)
        .. u32(total_length)
        .. u32(#json)
        .. u32(0x4E4F534A)
        .. json
        .. u32(#binary)
        .. u32(0x004E4942)
        .. binary
end

local glb = fixture_glb()
love.filesystem.read = function()
    return glb
end

local Material = libRequire("ddd-3d", "scripts.scene.material")
local GLBLoader = libRequire("ddd-3d", "scripts.scene.glb_loader")
local Runtime = libRequire("ddd-3d", "scripts.runtime")

local material = assert(Material.new({
    specularStrength = 0,
    ambientReflection = 0,
    normalStrength = 0.25,
    uvScale = { 2, 3 },
    normalMap = "normal.jpg",
    roughnessTexture = "roughness.jpg",
}))
local clone = assert(material:clone())
assert(clone.specular_strength == 0)
assert(clone.ambient_reflection == 0)
assert(clone.normal_strength == 0.25)
assert(clone.uv_scale[1] == 2 and clone.uv_scale[2] == 3)
assert(clone.normal_texture == "normal.jpg")
assert(clone.roughness_texture == "roughness.jpg")

local sent = {}
local shader = {
    hasUniform = function()
        return true
    end,
    send = function(_, name, value)
        sent[name] = value
    end,
}
assert(material:apply(shader))
assert(sent.u_specular_strength == 0)
assert(sent.u_ambient_reflection == 0)
assert(sent.u_normal_strength == 0.25)
assert(sent.u_uv_scale[1] == 2 and sent.u_uv_scale[2] == 3)

local hex_material = assert(Material.new({
    base_color = "#12345678",
    emissive = "#ABC",
}))
assert(math.abs(hex_material.base_color[1] - 0x12 / 255) < 0.00001)
assert(math.abs(hex_material.base_color[2] - 0x34 / 255) < 0.00001)
assert(math.abs(hex_material.base_color[3] - 0x56 / 255) < 0.00001)
assert(math.abs(hex_material.base_color[4] - 0x78 / 255) < 0.00001)
assert(math.abs(hex_material.emissive[1] - 0xAA / 255) < 0.00001)
assert(math.abs(hex_material.emissive[2] - 0xBB / 255) < 0.00001)
assert(math.abs(hex_material.emissive[3] - 0xCC / 255) < 0.00001)
assert(Material.isHexColor("#123456"))
assert(Material.isHexColor("#1234"))
assert(not Material.isHexColor("#12345"))
assert(hex_material:release())

local resolved = assert(Material.resolveTexturePaths({
    normalMap = "normal.jpg",
    roughnessTexture = "roughness.jpg",
}, function(path)
    return "/fixture-assets/" .. path
end))
assert(resolved.normal_texture == "/fixture-assets/normal.jpg")
assert(resolved.roughness_texture == "/fixture-assets/roughness.jpg")
local invalid_texture, invalid_field, invalid_texture_err = Material.validateTexturePaths({ normalMap = false })
assert(not invalid_texture and invalid_field == "normalMap")
assert(invalid_texture_err:find("texture path", 1, true))

local inline_model = assert(GLBLoader.loadData(glb, {
    material_overrides = {
        suit_outline_metal = {
            baseColor = { 0.70, 0.10, 0.90, 1 },
            alphaMode = "MASK",
            alphaCutoff = 0.25,
            doubleSided = true,
            specularStrength = 0.35,
            ambientReflection = 0.60,
            normalStrength = 0.20,
            uvScale = { 2, 3 },
            normalMap = "normal.jpg",
            roughnessTexture = "roughness.jpg",
        },
        suit_fill_black = {
            base_color = { 0.01, 0.01, 0.02, 1 },
            specular_strength = 0,
            ambient_reflection = 0,
        },
    },
}))
assert(inline_model:requireUniqueMaterial("suit_outline_metal"))
assert(inline_model:requireUniqueMaterial("suit_fill_black"))
local outline = inline_model.materials[1]
local fill = inline_model.materials[2]
assert(outline.base_color[1] == 0.70)
assert(outline.alpha_mode == "MASK")
assert(outline.alpha_cutoff == 0.25)
assert(outline.double_sided == true)
assert(outline.specular_strength == 0.35)
assert(outline.ambient_reflection == 0.60)
assert(outline.normal_strength == 0.20)
assert(outline.uv_scale[1] == 2 and outline.uv_scale[2] == 3)
assert(outline.normal_texture == "normal.jpg")
assert(outline.roughness_texture == "roughness.jpg")
assert(fill.specular_strength == 0)
assert(fill.ambient_reflection == 0)
assert(inline_model:release())

-- A Blender-native GLB keeps Z-up source transforms. The library applies the
-- basis exactly once, including when a named authored root is instantiated.
local blender_model = assert(GLBLoader.loadData(glb, {
    coordinate_space = "blender_z_up",
}))
local blender_instance = assert(blender_model:instantiate({
    node = "DDD_SCENE_ROOT",
    position = { 1, 2, 3 },
    rotation = { 0, 0, 0, 1 },
}))
blender_instance:updateWorldMatrix()
local blender_anchor = assert(blender_instance:find("anchor_camera"))
-- Source anchor B(0, 0, 2) becomes E(0, -2, 0), then receives the outer
-- engine-space placement E(1, 2, 3).
assert(math.abs(blender_anchor.world_matrix[13] - 1) < 0.00001)
assert(math.abs(blender_anchor.world_matrix[14] - 0) < 0.00001)
assert(math.abs(blender_anchor.world_matrix[15] - 3) < 0.00001)
-- Source B(0, -3, 0) retains Blender forward as renderer E(0, 0, 3).
local blender_suits = assert(blender_instance:find("suits"))
assert(math.abs(blender_suits.world_matrix[13] - 1) < 0.00001)
assert(math.abs(blender_suits.world_matrix[14] - 2) < 0.00001)
assert(math.abs(blender_suits.world_matrix[15] - 6) < 0.00001)
assert(blender_model:release())

local invalid_space, invalid_space_err = GLBLoader.loadData(glb, {
    coordinate_space = "unexpected",
})
assert(not invalid_space and invalid_space_err:find("coordinate_space", 1, true))

fixture_has_duplicate_material = true
local duplicate_model = assert(GLBLoader.loadData(glb))
local duplicate, duplicate_err = duplicate_model:requireUniqueMaterial("suit_outline_metal")
assert(not duplicate and duplicate_err:find("duplicate", 1, true))
assert(duplicate_model:release())
fixture_has_duplicate_material = false

local function definition()
    return {
        version = 2,
        materials = {
            purple_outline = {
                baseColor = { 0.70, 0.10, 0.90, 1 },
                alphaMode = "MASK",
                alphaCutoff = 0.25,
                doubleSided = true,
                specularStrength = 0.35,
                ambientReflection = 0.60,
                normalStrength = 0.20,
                uvScale = { 2, 3 },
                normalMap = "textures/normal.jpg",
                roughnessTexture = "textures/roughness.jpg",
            },
            black_fill = {
                base_color = { 0.01, 0.01, 0.02, 1 },
                specular_strength = 0,
                ambient_reflection = 0,
            },
        },
        authored_scene = {
            path = "fixture.glb",
            coordinate_space = "blender_z_up",
            root = "DDD_SCENE_ROOT",
            required_nodes = {
                "DDD_SCENE_ROOT",
                "anchor_camera",
                "anchor_camera_target",
                "swing_pivot",
                "chain",
                "suits",
            },
            material_overrides = {
                suit_outline_metal = "purple_outline",
                suit_fill_black = "black_fill",
            },
            camera = {
                anchor = "anchor_camera",
                target_anchor = "anchor_camera_target",
            },
            motions = {
                {
                    node = "swing_pivot",
                    kind = "sway",
                    axis = { 0, 0, 1 },
                    amplitude = 0.2,
                    speed = 1,
                    secondary_axis = { 0, 1, 0 },
                    secondary_amplitude = 0.05,
                    secondary_speed = 1.7,
                },
                {
                    node = "chain",
                    kind = "chain_sway",
                    terminal = "suits",
                    axis = { 0, 0, 1 },
                    amplitude = 0.5,
                    speed = 0.4,
                    phase = 1.2,
                    link_axis = { 0, 0, 1 },
                    link_amplitude = 0.35,
                    link_phase_lag = 0.5,
                    link_min_weight = 0.1,
                    link_curve = 1.2,
                },
            },
        },
        scene = {
            light = {
                fill = {
                    direction = { 0.4, -0.3, 0.7 },
                    color = { 0.2, 0.1, 0.5 },
                    strength = 0.15,
                },
            },
        },
    }
end

assert(Runtime.validateDefinition(definition()))
local hex_definition = definition()
hex_definition.materials.purple_outline.baseColor = "#B319E6"
hex_definition.materials.purple_outline.emissive = "#6A00FF"
assert(Runtime.validateDefinition(hex_definition))
hex_definition.materials.purple_outline.baseColor = "#12345"
local valid_hex_definition, hex_definition_err = Runtime.validateDefinition(hex_definition)
assert(not valid_hex_definition and hex_definition_err:find("hex color", 1, true))
local runtime = assert(Runtime.new(definition(), { asset_root = "/fixture-assets" }))
local runtime_outline = runtime.models.authored_scene.materials[1]
local runtime_fill = runtime.models.authored_scene.materials[2]
assert(runtime_outline.name == "purple_outline")
assert(runtime_outline.specular_strength == 0.35)
assert(runtime_outline.ambient_reflection == 0.60)
assert(runtime_outline.normal_strength == 0.20)
assert(runtime_outline.uv_scale[1] == 2 and runtime_outline.uv_scale[2] == 3)
assert(runtime_outline.normal_texture == "/fixture-assets/textures/normal.jpg")
assert(runtime_outline.roughness_texture == "/fixture-assets/textures/roughness.jpg")
assert(runtime_fill.name == "black_fill")
assert(runtime_fill.specular_strength == 0)
assert(runtime_fill.ambient_reflection == 0)
local swing_pivot = assert(runtime:getNode("swing_pivot"))
local chain = assert(runtime:getNode("chain"))
local suits = assert(runtime:getNode("suits"))
assert(suits.parent == swing_pivot)
assert(runtime:update(1))
assert(math.abs(swing_pivot.rotation[3]) > 0.01)
assert(math.abs(suits.world_matrix[13]) > 0.01)
assert(math.abs(suits.rotation[3]) > 0.01)
local upper_link = assert(chain:find("chain_link_00"))
local lower_link = assert(chain:find("chain_link_01"))
assert(upper_link.user_data.ddd_link_index == 0)
assert(lower_link.user_data.ddd_link_index == 1)
assert(math.abs(lower_link.rotation[3]) > math.abs(upper_link.rotation[3]))
assert(runtime:release())

local invalid_authored_motion = definition()
invalid_authored_motion.authored_scene.motions[1].node = "missing_pivot"
local valid_authored_motion, authored_motion_err = Runtime.validateDefinition(invalid_authored_motion)
assert(not valid_authored_motion and authored_motion_err:find("required_nodes", 1, true))

local invalid_chain_terminal = definition()
invalid_chain_terminal.authored_scene.motions[2].terminal = "missing_terminal"
local valid_chain_terminal, chain_terminal_err = Runtime.validateDefinition(invalid_chain_terminal)
assert(not valid_chain_terminal and chain_terminal_err:find("required_nodes", 1, true))

local invalid_coordinate_space = definition()
invalid_coordinate_space.authored_scene.coordinate_space = "unexpected"
local valid_coordinate_space, coordinate_space_err = Runtime.validateDefinition(invalid_coordinate_space)
assert(not valid_coordinate_space and coordinate_space_err:find("coordinate_space", 1, true))

local missing = definition()
missing.authored_scene.material_overrides.missing_material = "purple_outline"
local missing_runtime, missing_err = Runtime.new(missing)
assert(not missing_runtime and missing_err:find("has no material", 1, true))

local invalid_strength = definition()
invalid_strength.materials.purple_outline.normalStrength = math.huge
local valid_strength, strength_err = Runtime.validateDefinition(invalid_strength)
assert(not valid_strength and strength_err:find("normalStrength", 1, true))

local invalid_fill = definition()
invalid_fill.scene.light.fill.strength = 0 / 0
local valid_fill, fill_err = Runtime.validateDefinition(invalid_fill)
assert(not valid_fill and fill_err:find("scene.light.fill.strength", 1, true))

print("ddd-3d material contract: PASS")
