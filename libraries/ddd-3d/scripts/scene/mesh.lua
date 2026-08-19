local Mesh = {}
Mesh.__index = Mesh

Mesh.VERTEX_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexTangent", "float", 4 },
}

local function graphics_ready()
    return love and love.graphics and love.graphics.isActive and love.graphics.isActive()
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validate_vertex(vertex, index)
    if type(vertex) ~= "table" then
        return nil, "vertex " .. index .. " is not a table"
    end
    if #vertex ~= 8 and #vertex ~= 12 then
        return nil, "vertex " .. index .. " must contain 8 attributes or 12 attributes with a tangent"
    end
    for component = 1, #vertex do
        if not finite(vertex[component]) then
            return nil, "vertex " .. index .. " has an invalid component"
        end
    end
    return true
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1],
    }
end

local function normalize(value, fallback)
    local length = math.sqrt(dot(value, value))
    if length <= 0.000001 then
        return { fallback[1], fallback[2], fallback[3] }
    end
    return { value[1] / length, value[2] / length, value[3] / length }
end

local function fallback_tangent(normal)
    local reference = math.abs(normal[3]) < 0.999 and { 0, 0, 1 } or { 0, 1, 0 }
    return normalize(cross(reference, normal), { 1, 0, 0 })
end

local function vertex_map(vertices, indices)
    if indices then
        return indices
    end
    local map = {}
    for index = 1, #vertices do
        map[index] = index
    end
    return map
end

local function generate_tangents(vertices, indices)
    local tangent_sums = {}
    local bitangent_sums = {}
    for index = 1, #vertices do
        tangent_sums[index] = { 0, 0, 0 }
        bitangent_sums[index] = { 0, 0, 0 }
    end

    local map = vertex_map(vertices, indices)
    for offset = 1, #map - 2, 3 do
        local a, b, c = map[offset], map[offset + 1], map[offset + 2]
        local first, second, third = vertices[a], vertices[b], vertices[c]
        local edge_ab = { second[1] - first[1], second[2] - first[2], second[3] - first[3] }
        local edge_ac = { third[1] - first[1], third[2] - first[2], third[3] - first[3] }
        local du_ab, dv_ab = second[7] - first[7], second[8] - first[8]
        local du_ac, dv_ac = third[7] - first[7], third[8] - first[8]
        local determinant = du_ab * dv_ac - du_ac * dv_ab
        if math.abs(determinant) > 0.000001 then
            local inverse = 1 / determinant
            local tangent = {
                (edge_ab[1] * dv_ac - edge_ac[1] * dv_ab) * inverse,
                (edge_ab[2] * dv_ac - edge_ac[2] * dv_ab) * inverse,
                (edge_ab[3] * dv_ac - edge_ac[3] * dv_ab) * inverse,
            }
            local bitangent = {
                (edge_ac[1] * du_ab - edge_ab[1] * du_ac) * inverse,
                (edge_ac[2] * du_ab - edge_ab[2] * du_ac) * inverse,
                (edge_ac[3] * du_ab - edge_ab[3] * du_ac) * inverse,
            }
            for _, index in ipairs({ a, b, c }) do
                for component = 1, 3 do
                    tangent_sums[index][component] = tangent_sums[index][component] + tangent[component]
                    bitangent_sums[index][component] = bitangent_sums[index][component] + bitangent[component]
                end
            end
        end
    end

    local tangents = {}
    for index, vertex in ipairs(vertices) do
        local normal = normalize({ vertex[4], vertex[5], vertex[6] }, { 0, 0, 1 })
        local sum = tangent_sums[index]
        local projected = {
            sum[1] - normal[1] * dot(normal, sum),
            sum[2] - normal[2] * dot(normal, sum),
            sum[3] - normal[3] * dot(normal, sum),
        }
        local tangent = normalize(projected, fallback_tangent(normal))
        local bitangent = bitangent_sums[index]
        local handedness = dot(cross(normal, tangent), bitangent) < 0 and -1 or 1
        tangents[index] = { tangent[1], tangent[2], tangent[3], handedness }
    end
    return tangents
end

local function vertices_with_tangents(vertices, indices)
    local needs_tangents = false
    for _, vertex in ipairs(vertices) do
        if #vertex == 8 then
            needs_tangents = true
            break
        end
    end
    local generated = needs_tangents and generate_tangents(vertices, indices) or nil
    local result = {}
    for index, vertex in ipairs(vertices) do
        local tangent = generated and generated[index] or { vertex[9], vertex[10], vertex[11], vertex[12] }
        result[index] = {
            vertex[1], vertex[2], vertex[3],
            vertex[4], vertex[5], vertex[6],
            vertex[7], vertex[8],
            tangent[1], tangent[2], tangent[3], tangent[4],
        }
    end
    return result
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

    local gpu_vertices = vertices_with_tangents(vertices, indices)

    local ok, handle = pcall(love.graphics.newMesh, Mesh.VERTEX_FORMAT, gpu_vertices, "triangles", options.usage or "static")
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
        vertices = gpu_vertices,
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
