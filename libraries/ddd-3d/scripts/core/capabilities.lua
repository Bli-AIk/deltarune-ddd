local Capabilities = {}

local depth_candidates = {
    "depth24stencil8",
    "depth32f",
    "depth24",
    "depth16",
}

local color_candidates = {
    "rgba8",
    "normal",
}

local function graphics_ready()
    return love and love.graphics and love.graphics.isActive and love.graphics.isActive()
end

local function release_if_possible(resource)
    if resource and resource.release then
        pcall(resource.release, resource)
    end
end

local function can_create_canvas(format)
    local ok, canvas = pcall(love.graphics.newCanvas, 1, 1, { format = format })
    if ok then
        release_if_possible(canvas)
    end
    return ok
end

local function get_canvas_formats()
    if not graphics_ready() or not love.graphics.getCanvasFormats then
        return nil
    end
    local ok, formats = pcall(love.graphics.getCanvasFormats)
    if ok and type(formats) == "table" then
        return formats
    end
    return nil
end

local function choose_format(requested, candidates, formats)
    if requested and requested ~= "auto" then
        if not formats or formats[requested] then
            if can_create_canvas(requested) then
                return requested
            end
        end
        return nil, "canvas format is unavailable: " .. tostring(requested)
    end

    for _, format in ipairs(candidates) do
        if (not formats or formats[format]) and can_create_canvas(format) then
            return format
        end
    end
    return nil, "no supported canvas format was found"
end

--- Returns a capability snapshot without assuming that 3D is available.
function Capabilities.get()
    local result = {
        graphics_active = graphics_ready(),
        depth = false,
        depth_format = nil,
        color_format = nil,
        cull = false,
        front_face = false,
    }

    if not result.graphics_active then
        result.error = "love.graphics is not active"
        return result
    end

    local formats = get_canvas_formats()
    result.color_format = choose_format(nil, color_candidates, formats)
    result.depth_format = choose_format(nil, depth_candidates, formats)
    result.depth = result.depth_format ~= nil
    result.cull = type(love.graphics.setMeshCullMode) == "function"
    result.front_face = type(love.graphics.setFrontFaceWinding) == "function"
    return result
end

--- Creates separate color and depth canvases suitable for a 3D render pass.
---@return table? pair
---@return string? err
function Capabilities.newCanvasPair(width, height, options)
    options = options or {}
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width < 1 or height < 1 then
        return nil, "canvas dimensions must be positive"
    end
    if not graphics_ready() then
        return nil, "love.graphics is not active"
    end

    local formats = get_canvas_formats()
    local color_format, color_err = choose_format(options.color_format, color_candidates, formats)
    if not color_format then
        return nil, color_err
    end
    local depth_format, depth_err = choose_format(options.depth_format, depth_candidates, formats)
    if not depth_format then
        return nil, depth_err
    end

    local color_settings = { format = color_format }
    -- The depth target is only attached to the render pass and never sampled.
    -- Marking it unreadable also keeps depth+MSAA valid on LÖVE 11.5.
    local depth_settings = { format = depth_format, readable = false }
    if options.msaa and options.msaa > 0 then
        color_settings.msaa = options.msaa
        depth_settings.msaa = options.msaa
    end

    local ok_color, color = pcall(love.graphics.newCanvas, width, height, color_settings)
    if not ok_color then
        return nil, "could not create color canvas: " .. tostring(color)
    end
    local ok_depth, depth = pcall(love.graphics.newCanvas, width, height, depth_settings)
    if not ok_depth then
        release_if_possible(color)
        return nil, "could not create depth canvas: " .. tostring(depth)
    end

    return {
        color = color,
        depth = depth,
        width = width,
        height = height,
        color_format = color_format,
        depth_format = depth_format,
    }
end

function Capabilities.releaseCanvasPair(pair)
    if type(pair) ~= "table" then
        return true
    end
    release_if_possible(pair.color)
    release_if_possible(pair.depth)
    pair.color = nil
    pair.depth = nil
    return true
end

local function query(function_name)
    local fn = love and love.graphics and love.graphics[function_name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, first, second, third, fourth = pcall(fn)
    if not ok then
        return nil
    end
    return { first, second, third, fourth }
end

--- Kristal's push("all") intentionally does not retain these states.
function Capabilities.captureSpecialState()
    return {
        depth = query("getDepthMode"),
        cull = query("getMeshCullMode"),
        front_face = query("getFrontFaceWinding"),
    }
end

function Capabilities.restoreSpecialState(state)
    if not state or not love or not love.graphics then
        return
    end
    if state.depth and love.graphics.setDepthMode then
        pcall(love.graphics.setDepthMode, state.depth[1], state.depth[2])
    end
    if state.cull and love.graphics.setMeshCullMode then
        pcall(love.graphics.setMeshCullMode, state.cull[1])
    end
    if state.front_face and love.graphics.setFrontFaceWinding then
        pcall(love.graphics.setFrontFaceWinding, state.front_face[1])
    end
end

return Capabilities
