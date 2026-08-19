local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Transform = libRequire(LIB_ID, "scripts.scene.transform")

local Node = {}
Node.__index = Node

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function has_ancestor(node, candidate)
    local current = node
    while current do
        if current == candidate then
            return true
        end
        current = current.parent
    end
    return false
end

function Node.new(options)
    options = options or {}
    local self = setmetatable({}, Node)
    self.name = options.name or "node"
    self.transform = options.transform or Transform.new(options)
    self.position = self.transform.position
    self.rotation = self.transform.rotation
    self.scale = self.transform.scale
    self.mesh = options.mesh
    self.material = options.material
    self.visible = options.visible ~= false
    self.enabled = options.enabled ~= false
    self.parent = nil
    self.children = {}
    self.world_matrix = Math3D.mat4Identity()
    self.user_data = options.user_data or {}
    self.onUpdate = options.onUpdate
    return self
end

function Node:setPosition(x, y, z)
    self.transform:setPosition(x, y, z)
    self.position = self.transform.position
    return self
end

function Node:setScale(x, y, z)
    self.transform:setScale(x, y, z)
    self.scale = self.transform.scale
    return self
end

function Node:setRotation(x, y, z, w)
    self.transform:setRotation(x, y, z, w)
    self.rotation = self.transform.rotation
    return self
end

function Node:setEuler(x, y, z)
    self.transform:setEuler(x, y, z)
    self.rotation = self.transform.rotation
    return self
end

function Node:setMatrix(matrix)
    local ok, err = self.transform:setMatrix(matrix)
    if not ok then
        return nil, err
    end
    return self
end

function Node:getLocalMatrix()
    -- Direct field replacement is intentionally supported for scene scripts.
    self.transform.position = self.position or self.transform.position
    self.transform.rotation = self.rotation or self.transform.rotation
    self.transform.scale = self.scale or self.transform.scale
    return self.transform:getMatrix()
end

function Node:addChild(child)
    if type(child) ~= "table" or getmetatable(child) ~= Node then
        return nil, "child must be a ddd-3d node"
    end
    if child == self or has_ancestor(self, child) then
        return nil, "cannot create a cyclic node hierarchy"
    end
    if child.parent then
        child.parent:removeChild(child)
    end
    child.parent = self
    self.children[#self.children + 1] = child
    return child
end

function Node:removeChild(child)
    for index, current in ipairs(self.children) do
        if current == child then
            table.remove(self.children, index)
            child.parent = nil
            return child
        end
    end
    return nil, "node is not a child of this parent"
end

function Node:find(name)
    if self.name == name then
        return self
    end
    for _, child in ipairs(self.children) do
        local found = child:find(name)
        if found then
            return found
        end
    end
    return nil
end

function Node:traverse(callback)
    if type(callback) ~= "function" then
        return nil, "traverse callback must be a function"
    end
    local should_continue = callback(self)
    if should_continue == false then
        return false
    end
    for _, child in ipairs(self.children) do
        if child:traverse(callback) == false then
            return false
        end
    end
    return true
end

function Node:updateWorldMatrix(parent_matrix)
    local local_matrix = self:getLocalMatrix()
    self.world_matrix = parent_matrix and Math3D.multiplyMat4(parent_matrix, local_matrix) or Math3D.copyMat4(local_matrix)
    for _, child in ipairs(self.children) do
        child:updateWorldMatrix(self.world_matrix)
    end
    return self.world_matrix
end

function Node:clone(options)
    options = options or {}
    local clone = Node.new({
        name = options.name or self.name,
        transform = self.transform:clone(),
        mesh = options.mesh or self.mesh,
        material = options.material or self.material,
        visible = options.visible == nil and self.visible or options.visible,
        enabled = options.enabled == nil and self.enabled or options.enabled,
        user_data = options.user_data or copy_table(self.user_data),
        onUpdate = options.onUpdate or self.onUpdate,
    })
    for _, child in ipairs(self.children) do
        local child_clone = child:clone()
        clone:addChild(child_clone)
    end
    return clone
end

return Node
