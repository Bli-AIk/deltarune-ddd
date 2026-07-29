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
            { name = "suits", mesh = 0 },
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
}))
local clone = assert(material:clone())
assert(clone.specular_strength == 0)
assert(clone.ambient_reflection == 0)

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

local inline_model = assert(GLBLoader.loadData(glb, {
    material_overrides = {
        suit_outline_metal = {
            baseColor = { 0.70, 0.10, 0.90, 1 },
            alphaMode = "MASK",
            alphaCutoff = 0.25,
            doubleSided = true,
            specularStrength = 0.35,
            ambientReflection = 0.60,
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
assert(fill.specular_strength == 0)
assert(fill.ambient_reflection == 0)
assert(inline_model:release())

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
            },
            black_fill = {
                base_color = { 0.01, 0.01, 0.02, 1 },
                specular_strength = 0,
                ambient_reflection = 0,
            },
        },
        authored_scene = {
            path = "fixture.glb",
            root = "DDD_SCENE_ROOT",
            required_nodes = {
                "DDD_SCENE_ROOT",
                "anchor_camera",
                "anchor_camera_target",
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
        },
    }
end

assert(Runtime.validateDefinition(definition()))
local runtime = assert(Runtime.new(definition()))
local runtime_outline = runtime.models.authored_scene.materials[1]
local runtime_fill = runtime.models.authored_scene.materials[2]
assert(runtime_outline.name == "purple_outline")
assert(runtime_outline.specular_strength == 0.35)
assert(runtime_outline.ambient_reflection == 0.60)
assert(runtime_fill.name == "black_fill")
assert(runtime_fill.specular_strength == 0)
assert(runtime_fill.ambient_reflection == 0)
assert(runtime:release())

local missing = definition()
missing.authored_scene.material_overrides.missing_material = "purple_outline"
local missing_runtime, missing_err = Runtime.new(missing)
assert(not missing_runtime and missing_err:find("has no material", 1, true))

print("ddd-3d material contract: PASS")
