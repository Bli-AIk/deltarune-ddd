local Mesh = {}
Mesh.__index = Mesh

Mesh.VERTEX_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}

local function graphics_ready()
    return love and love.graphics and love.graphics.isActive and love.graphics.isActive()
end

local function validate_vertex(vertex, index)
    if type(vertex) ~= "table" then
        return nil, "vertex " .. index .. " is not a table"
    end
    for component = 1, 8 do
        if type(vertex[component]) ~= "number" then
            return nil, "vertex " .. index .. " has an invalid component"
        end
    end
    return true
end

local function calculate_bounds(vertices)
    local minimum = { math.huge, math.huge, math.huge }
    local maximum = { -math.huge, -math.huge, -math.huge }
    for _, vertex in ipairs(vertices) do
        for axis = 1, 3 do
            minimum[axis] = math.min(minimum[axis], vertex[axis])
            maximum[axis] = math.max(maximum[axis], vertex[axis])
        end
    end
    return { min = minimum, max = maximum }
end

--- Creates a LÖVE mesh with POSITION, NORMAL, and TEXCOORD_0 data.
---@param vertices number[][]
---@param indices? number[]
---@param options? table
---@return table? mesh
---@return string? err
function Mesh.new(vertices, indices, options)
    options = options or {}
    if not graphics_ready() then
        return nil, "love.graphics is not active"
    end
    if type(vertices) ~= "table" or #vertices == 0 then
        return nil, "mesh requires at least one vertex"
    end
    for index, vertex in ipairs(vertices) do
        local valid, err = validate_vertex(vertex, index)
        if not valid then
            return nil, err
        end
    end
    if indices then
        if type(indices) ~= "table" or #indices == 0 then
            return nil, "mesh indices must be a non-empty table"
        end
        for index, vertex_index in ipairs(indices) do
            if type(vertex_index) ~= "number" or vertex_index % 1 ~= 0 or vertex_index < 1 or vertex_index > #vertices then
                return nil, "mesh index " .. index .. " is out of range"
            end
        end
    end

    local ok, handle = pcall(love.graphics.newMesh, Mesh.VERTEX_FORMAT, vertices, "triangles", options.usage or "static")
    if not ok then
        return nil, "could not create LÖVE mesh: " .. tostring(handle)
    end
    if indices then
        local mapped, map_err = pcall(handle.setVertexMap, handle, indices)
        if not mapped then
            if handle.release then
                pcall(handle.release, handle)
            end
            return nil, "could not set mesh index buffer: " .. tostring(map_err)
        end
    end

    return setmetatable({
        handle = handle,
        vertices = vertices,
        indices = indices,
        bounds = calculate_bounds(vertices),
        material = options.material,
        name = options.name or "mesh",
        released = false,
    }, Mesh)
end

function Mesh:isReleased()
    return self.released or not self.handle
end

function Mesh:release()
    if self.released then
        return true
    end
    if self.handle and self.handle.release then
        local ok, err = pcall(self.handle.release, self.handle)
        if not ok then
            return nil, "could not release mesh: " .. tostring(err)
        end
    end
    self.handle = nil
    self.released = true
    return true
end

return Mesh
