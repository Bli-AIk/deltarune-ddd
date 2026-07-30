local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Node = libRequire(LIB_ID, "scripts.scene.node")
local Camera = libRequire(LIB_ID, "scripts.scene.camera")
local Mesh = libRequire(LIB_ID, "scripts.scene.mesh")
local Renderer = libRequire(LIB_ID, "scripts.scene.renderer")

local Scene = {}
Scene.__index = Scene

local function copy_color(value, fallback)
    value = value or fallback
    return {
        tonumber(value[1]) or 0,
        tonumber(value[2]) or 0,
        tonumber(value[3]) or 0,
        tonumber(value[4]) == nil and 1 or tonumber(value[4]),
    }
end

local function copy_vec3(value, fallback)
    value = value or fallback
    return {
        tonumber(value[1]) or 0,
        tonumber(value[2]) or 0,
        tonumber(value[3]) or 0,
    }
end

local function non_negative_number(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(0, value)
end

local function copy_point_lights(value)
    local points = {}
    for index, point in ipairs(value or {}) do
        if index > 4 or type(point) ~= "table" then
            break
        end
        points[index] = {
            position = copy_vec3(point.position, { 0, 0, 0 }),
            color = copy_vec3(point.color, { 0, 0, 0 }),
            strength = non_negative_number(point.strength, 0),
            range = math.max(0.001, non_negative_number(point.range, 1)),
        }
    end
    return points
end

local function apply_node_options(node, options)
    if options.position then node:setPosition(options.position) end
    if options.rotation then node:setRotation(options.rotation) end
    if options.scale then node:setScale(options.scale) end
    if options.matrix then
        local changed, err = node:setMatrix(options.matrix)
        if not changed then return nil, err end
    end
    if options.name then node.name = options.name end
    if options.visible ~= nil then node.visible = options.visible end
    if options.enabled ~= nil then node.enabled = options.enabled end
    if options.material then
        node:traverse(function(current)
            if current.mesh then
                current.material = options.material
            end
        end)
    end
    if options.onUpdate then node.onUpdate = options.onUpdate end
    return node
end

function Scene.new(options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, "scene options must be a table"
    end
    local renderer, renderer_err = Renderer.new(options.renderer)
    if not renderer then
        return nil, renderer_err
    end
    local camera_options = options.camera or {}
    local camera = options.camera_instance or Camera.new(camera_options)
    if type(camera) ~= "table" or type(camera.getViewProjectionMatrix) ~= "function" then
        return nil, "scene camera must be a ddd-3d camera"
    end
    local self = setmetatable({
        root = Node.new({ name = "scene_root" }),
        camera = camera,
        renderer = renderer,
        clear_color = copy_color(options.clear_color, { 0, 0, 0, 0 }),
        width = options.width,
        height = options.height,
        time = 0,
        light = {
            direction = Math3D.normalize3((options.light and options.light.direction) or { -0.35, -0.7, -0.55 }, { 0, -1, 0 }),
            color = copy_vec3(options.light and options.light.color, { 1, 1, 1 }),
            ambient = copy_vec3(options.light and options.light.ambient, { 0.16, 0.19, 0.26 }),
            fill = {
                direction = Math3D.normalize3(
                    (options.light and options.light.fill and options.light.fill.direction) or { 0.45, -0.35, 0.65 },
                    { 0, -1, 0 }
                ),
                color = copy_vec3(
                    options.light and options.light.fill and options.light.fill.color,
                    { 1, 1, 1 }
                ),
                strength = non_negative_number(
                    options.light and options.light.fill and options.light.fill.strength,
                    0
                ),
            },
            point_lights = copy_point_lights(options.light and options.light.point_lights),
        },
        released = false,
    }, Scene)
    return self
end

function Scene:setCamera(camera)
    if type(camera) ~= "table" or type(camera.getViewProjectionMatrix) ~= "function" then
        return nil, "scene camera must be a ddd-3d camera"
    end
    self.camera = camera
    return camera
end

function Scene:setClearColor(color)
    if type(color) ~= "table" then
        return nil, "clear color must be a color table"
    end
    self.clear_color = copy_color(color, self.clear_color)
    return self
end

function Scene:setLight(light)
    if type(light) ~= "table" then
        return nil, "light settings must be a table"
    end
    if light.direction then
        self.light.direction = Math3D.normalize3(light.direction, { 0, -1, 0 })
    end
    if light.color then
        self.light.color = copy_vec3(light.color, self.light.color)
    end
    if light.ambient then
        self.light.ambient = copy_vec3(light.ambient, self.light.ambient)
    end
    if light.fill then
        if type(light.fill) ~= "table" then
            return nil, "scene fill light settings must be a table"
        end
        if light.fill.direction then
            self.light.fill.direction = Math3D.normalize3(light.fill.direction, { 0, -1, 0 })
        end
        if light.fill.color then
            self.light.fill.color = copy_vec3(light.fill.color, self.light.fill.color)
        end
        if light.fill.strength ~= nil then
            self.light.fill.strength = non_negative_number(light.fill.strength, self.light.fill.strength)
        end
    end
    if light.point_lights ~= nil then
        if type(light.point_lights) ~= "table" then
            return nil, "scene point lights must be an array"
        end
        self.light.point_lights = copy_point_lights(light.point_lights)
    end
    return self
end

--- Adds a mesh, node, or model instance. Model options may include node = "name".
function Scene:spawn(prototype, options)
    if self.released then
        return nil, "scene has been released"
    end
    options = options or {}
    if type(options) ~= "table" then
        return nil, "spawn options must be a table"
    end
    local node, err
    if getmetatable(prototype) == Mesh then
        if prototype:isReleased() then
            return nil, "spawn cannot use a released mesh"
        end
        node = Node.new({
            name = options.name or prototype.name,
            mesh = prototype,
            material = options.material or prototype.material,
        })
        node, err = apply_node_options(node, options)
    elseif type(prototype) == "table" and type(prototype.instantiate) == "function" then
        if prototype.released then
            return nil, "spawn cannot use a released model"
        end
        node, err = prototype:instantiate(options)
    elseif getmetatable(prototype) == Node then
        node = prototype:clone()
        node, err = apply_node_options(node, options)
    else
        return nil, "spawn expected a ddd-3d mesh, node, or GLB model"
    end
    if not node then
        return nil, err
    end
    local parent = options.parent or self.root
    if getmetatable(parent) ~= Node then
        return nil, "spawn parent must be a ddd-3d node"
    end
    return parent:addChild(node)
end

function Scene:remove(node)
    if getmetatable(node) ~= Node then
        return nil, "remove expected a ddd-3d node"
    end
    if not node.parent then
        return nil, "node does not belong to a scene"
    end
    return node.parent:removeChild(node)
end

function Scene:traverse(callback)
    return self.root:traverse(callback)
end

function Scene:update(dt)
    if self.released then
        return nil, "scene has been released"
    end
    dt = tonumber(dt)
    if not dt or dt < 0 then
        return nil, "scene update delta must be a non-negative number"
    end
    self.time = self.time + dt
    local callback_error
    self.root:traverse(function(node)
        if node.enabled and node.onUpdate then
            local ok, err = pcall(node.onUpdate, node, dt, self)
            if not ok then
                callback_error = tostring(err)
                return false
            end
        end
    end)
    if callback_error then
        return nil, "scene node update failed: " .. callback_error
    end
    self.root:updateWorldMatrix()
    return true
end

function Scene:draw(options)
    if self.released then
        return nil, "scene has been released"
    end
    self.root:updateWorldMatrix()
    return self.renderer:draw(self, options)
end

function Scene:release()
    if self.released then
        return true
    end
    local ok, err = self.renderer:release()
    if not ok then
        return nil, err
    end
    self.root.children = {}
    self.released = true
    return true
end

return Scene
