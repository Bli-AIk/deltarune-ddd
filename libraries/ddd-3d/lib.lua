-- ddd-3d is intentionally self-contained: game code only talks to this table.
local LIB_ID = "ddd-3d"

local Capabilities = libRequire(LIB_ID, "scripts.core.capabilities")
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Transform = libRequire(LIB_ID, "scripts.scene.transform")
local Node = libRequire(LIB_ID, "scripts.scene.node")
local Camera = libRequire(LIB_ID, "scripts.scene.camera")
local Mesh = libRequire(LIB_ID, "scripts.scene.mesh")
local Material = libRequire(LIB_ID, "scripts.scene.material")
local GLBLoader = libRequire(LIB_ID, "scripts.scene.glb_loader")
local Scene = libRequire(LIB_ID, "scripts.scene.scene")
local Renderer = libRequire(LIB_ID, "scripts.scene.renderer")
local Runtime = libRequire(LIB_ID, "scripts.runtime")

local library = {
    id = LIB_ID,
    version = "0.1.0",
    capabilities = Capabilities,
    math = Math3D,
    Transform = Transform,
    Node = Node,
    Camera = Camera,
    Mesh = Mesh,
    Material = Material,
    Renderer = Renderer,
    Runtime = Runtime,
}

--- Creates an isolated 3D scene. GPU resources are allocated lazily by draw.
---@param options? table
---@return table? scene
---@return string? err
function library.newScene(options)
    return Scene.new(options)
end

--- Loads a Blender-compatible GLB 2.0 asset.
---@param path string
---@param options? table
---@return table? model
---@return string? err
function library.loadGLB(path, options)
    return GLBLoader.load(path, options)
end

--- Instantiates a model, node, or mesh into a scene.
---@param scene table
---@param prototype table
---@param options? table
---@return table? node
---@return string? err
function library.spawn(scene, prototype, options)
    if type(scene) ~= "table" or type(scene.spawn) ~= "function" then
        return nil, "ddd-3d.spawn expected a scene created by newScene"
    end
    return scene:spawn(prototype, options)
end

---@param scene table
---@param dt number
---@return boolean? ok
---@return string? err
function library.update(scene, dt)
    if type(scene) ~= "table" or type(scene.update) ~= "function" then
        return nil, "ddd-3d.update expected a scene created by newScene"
    end
    return scene:update(dt)
end

---@param scene table
---@param options? table
---@return love.Canvas? canvas
---@return string? err
function library.draw(scene, options)
    if type(scene) ~= "table" or type(scene.draw) ~= "function" then
        return nil, "ddd-3d.draw expected a scene created by newScene"
    end
    return scene:draw(options)
end

--- Releases a scene, model, mesh, material, or renderer when it owns GPU data.
---@param resource table?
---@return boolean? ok
---@return string? err
function library.release(resource)
    if resource == nil then
        return true
    end
    if type(resource) ~= "table" or type(resource.release) ~= "function" then
        return nil, "ddd-3d.release expected a releasable ddd-3d resource"
    end
    return resource:release()
end

function library.getCapabilities()
    return Capabilities.get()
end

--- Validates a data-only runtime preset before GPU resources are allocated.
function library.validateDefinition(definition)
    return Runtime.validateDefinition(definition)
end

--- Builds a restricted declarative runtime. The definition cannot execute code.
---@param definition table
---@param context? table
---@return table? runtime
---@return string? err
function library.newRuntime(definition, context)
    return Runtime.new(definition, context)
end

--- Captures a plain numeric map-camera snapshot for Runtime:update(dt, context).
function library.captureWorldContext(world, options)
    return Runtime.captureWorldContext(world, options)
end

-- Library consumers can use Mod.libs["ddd-3d"], while the global is useful
-- for interactive Kristal console work and follows existing library practice.
if Registry and Registry.registerGlobal then
    Registry.registerGlobal("DDD3D", library)
end

return library
