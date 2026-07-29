local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")

local Transform = {}
Transform.__index = Transform

function Transform.new(options)
    options = options or {}
    local self = setmetatable({}, Transform)
    self.position = Math3D.copy3(options.position, { 0, 0, 0 })
    self.rotation = Math3D.copyQuat(options.rotation)
    self.scale = Math3D.copy3(options.scale, { 1, 1, 1 })
    self.matrix = options.matrix and Math3D.copyMat4(options.matrix) or nil
    return self
end

function Transform:setPosition(x, y, z)
    if type(x) == "table" then
        self.position = Math3D.copy3(x)
    else
        self.position = { x or 0, y or 0, z or 0 }
    end
    self.matrix = nil
    return self
end

function Transform:setScale(x, y, z)
    if type(x) == "table" then
        self.scale = Math3D.copy3(x, { 1, 1, 1 })
    else
        self.scale = { x or 1, y == nil and (x or 1) or y, z == nil and (x or 1) or z }
    end
    self.matrix = nil
    return self
end

function Transform:setRotation(x, y, z, w)
    if type(x) == "table" then
        self.rotation = Math3D.normalizeQuat(Math3D.copyQuat(x))
    else
        self.rotation = Math3D.normalizeQuat({ x or 0, y or 0, z or 0, w == nil and 1 or w })
    end
    self.matrix = nil
    return self
end

function Transform:setEuler(x, y, z)
    self.rotation = Math3D.quatFromEuler(x, y, z)
    self.matrix = nil
    return self
end

function Transform:setMatrix(matrix)
    if type(matrix) ~= "table" or #matrix < 16 then
        return nil, "transform matrix must contain 16 values"
    end
    self.matrix = Math3D.copyMat4(matrix)
    return self
end

function Transform:getMatrix()
    if self.matrix then
        return self.matrix
    end
    -- Rebuilding here also respects intentional direct edits to position/scale.
    return Math3D.mat4FromTRS(self.position, self.rotation, self.scale)
end

function Transform:clone()
    return Transform.new({
        position = self.position,
        rotation = self.rotation,
        scale = self.scale,
        matrix = self.matrix,
    })
end

return Transform
