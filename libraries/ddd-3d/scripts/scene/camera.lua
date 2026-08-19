local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Transform = libRequire(LIB_ID, "scripts.scene.transform")

local Camera = {}
Camera.__index = Camera

function Camera.new(options)
    options = options or {}
    local self = setmetatable({}, Camera)
    self.transform = Transform.new({
        position = options.position or { 0, 0, 10 },
        rotation = options.rotation,
    })
    self.position = self.transform.position
    self.rotation = self.transform.rotation
    self.target = options.target and Math3D.copy3(options.target) or { 0, 0, 0 }
    self.up = Math3D.copy3(options.up, { 0, 1, 0 })
    self.fov = options.fov or math.rad(50)
    self.near = options.near or 0.1
    self.far = options.far or 1000
    return self
end

function Camera:setPosition(x, y, z)
    self.transform:setPosition(x, y, z)
    self.position = self.transform.position
    return self
end

function Camera:setRotation(x, y, z, w)
    self.transform:setRotation(x, y, z, w)
    self.rotation = self.transform.rotation
    self.target = nil
    return self
end

function Camera:setEuler(x, y, z)
    self.transform:setEuler(x, y, z)
    self.rotation = self.transform.rotation
    self.target = nil
    return self
end

function Camera:lookAt(target, up)
    if type(target) ~= "table" then
        return nil, "camera target must be a vec3 table"
    end
    self.target = Math3D.copy3(target)
    if up then
        self.up = Math3D.copy3(up, { 0, 1, 0 })
    end
    return self
end

function Camera:setFovRadians(fov)
    fov = tonumber(fov)
    if not fov or fov <= 0 or fov >= math.pi then
        return nil, "camera FOV must be between 0 and pi radians"
    end
    self.fov = fov
    return self
end

function Camera:setFovDegrees(fov)
    return self:setFovRadians(math.rad(tonumber(fov) or 0))
end

function Camera:getViewMatrix()
    self.transform.position = self.position or self.transform.position
    self.transform.rotation = self.rotation or self.transform.rotation
    if self.target then
        return Math3D.lookAt(self.position, self.target, self.up)
    end
    return Math3D.invertMat4(self.transform:getMatrix())
end

function Camera:getProjectionMatrix(aspect)
    return Math3D.perspective(self.fov, aspect, self.near, self.far)
end

function Camera:getViewProjectionMatrix(aspect)
    local projection, projection_err = self:getProjectionMatrix(aspect)
    if not projection then
        return nil, projection_err
    end
    local view, view_err = self:getViewMatrix()
    if not view then
        return nil, view_err
    end
    return Math3D.multiplyMat4(projection, view)
end

return Camera
