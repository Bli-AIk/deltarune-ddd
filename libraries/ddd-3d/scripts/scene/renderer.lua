local LIB_ID = "ddd-3d"
local Capabilities = libRequire(LIB_ID, "scripts.core.capabilities")
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")

local Renderer = {}
Renderer.__index = Renderer

local shader_names = { "lit", "emissive", "composite" }

local function graphics_ready()
    return love and love.graphics and love.graphics.isActive and love.graphics.isActive()
end

local function join_path(left, right)
    if left:sub(-1) == "/" then
        return left .. right
    end
    return left .. "/" .. right
end

local function library_path()
    if not Mod then
        return nil
    end
    if Mod.info and Mod.info.libs and Mod.info.libs[LIB_ID] then
        return Mod.info.libs[LIB_ID].path
    end
    if Mod.libs and Mod.libs[LIB_ID] and Mod.libs[LIB_ID].info then
        return Mod.libs[LIB_ID].info.path
    end
    return nil
end

local function read_text(path)
    if love and love.filesystem and love.filesystem.read then
        local ok, contents = pcall(love.filesystem.read, path)
        if ok and type(contents) == "string" then
            return contents
        end
    end
    if io and io.open then
        local opened, file = pcall(io.open, path, "rb")
        if opened and file then
            local read_ok, contents = pcall(file.read, file, "*a")
            pcall(file.close, file)
            if read_ok and type(contents) == "string" then
                return contents
            end
        end
    end
    return nil
end

local function release_if_possible(resource)
    if resource and resource.release then
        pcall(resource.release, resource)
    end
end

local function send(shader, name, value, is_matrix)
    if shader.hasUniform then
        local checked, has_uniform = pcall(shader.hasUniform, shader, name)
        if checked and not has_uniform then
            return true
        end
    end
    local ok, err
    if is_matrix then
        -- Math3D stores flat matrices in GLSL's native column-major order.
        ok, err = pcall(shader.send, shader, name, "column", value)
    else
        ok, err = pcall(shader.send, shader, name, value)
    end
    if not ok then
        return nil, "could not send shader uniform " .. name .. ": " .. tostring(err)
    end
    return true
end

local function canvas_dimensions()
    local current = love.graphics.getCanvas and love.graphics.getCanvas()
    if current and current.getDimensions then
        local ok, width, height = pcall(current.getDimensions, current)
        if ok and width and height then
            return width, height
        end
    end
    return love.graphics.getDimensions()
end

local function renderable_lists(node, inherited_visible, opaque, transparent)
    local visible = inherited_visible and node.visible ~= false and node.enabled ~= false
    if not visible then
        return
    end
    if node.mesh and not node.mesh:isReleased() then
        local material = node.material or node.mesh.material
        if material then
            local entry = { node = node, mesh = node.mesh, material = material }
            if material.alpha_mode == "BLEND" then
                transparent[#transparent + 1] = entry
            else
                opaque[#opaque + 1] = entry
            end
        end
    end
    for _, child in ipairs(node.children) do
        renderable_lists(child, visible, opaque, transparent)
    end
end

function Renderer.new(options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, "renderer options must be a table"
    end
    return setmetatable({
        color = nil,
        depth = nil,
        pair = nil,
        shaders = nil,
        shader_root = options.shader_root,
        color_format = options.color_format,
        depth_format = options.depth_format,
        msaa = options.msaa,
        released = false,
    }, Renderer)
end

function Renderer:_shaderSource(name)
    local roots = {}
    if self.shader_root then
        roots[#roots + 1] = self.shader_root
    end
    local registered_path = library_path()
    if registered_path then
        roots[#roots + 1] = join_path(registered_path, "assets/shaders")
    end
    roots[#roots + 1] = "libraries/" .. LIB_ID .. "/assets/shaders"
    for _, root in ipairs(roots) do
        local source = read_text(join_path(root, name .. ".glsl"))
        if source then
            return source
        end
    end
    return nil, "could not find library shader " .. name
end

function Renderer:_ensureShaders()
    if self.shaders then
        return true
    end
    if not graphics_ready() then
        return nil, "love.graphics is not active"
    end
    local shaders = {}
    for _, name in ipairs(shader_names) do
        local source, source_err = self:_shaderSource(name)
        if not source then
            for _, shader in pairs(shaders) do
                release_if_possible(shader)
            end
            return nil, source_err
        end
        local ok, shader = pcall(love.graphics.newShader, source)
        if not ok then
            for _, previous in pairs(shaders) do
                release_if_possible(previous)
            end
            return nil, "could not compile " .. name .. " shader: " .. tostring(shader)
        end
        shaders[name] = shader
    end
    self.shaders = shaders
    return true
end

function Renderer:_ensureTargets(width, height, options)
    if self.pair and self.pair.width == width and self.pair.height == height then
        return true
    end
    local pair, err = Capabilities.newCanvasPair(width, height, {
        color_format = options.color_format or self.color_format,
        depth_format = options.depth_format or self.depth_format,
        msaa = options.msaa or self.msaa,
    })
    if not pair then
        return nil, err
    end
    Capabilities.releaseCanvasPair(self.pair)
    self.pair = pair
    self.color = pair.color
    self.depth = pair.depth
    return true
end

function Renderer:_drawRenderable(entry, scene, view_projection)
    local material = entry.material
    if material.released then
        return nil, "material " .. tostring(material.name) .. " has been released"
    end
    local shader = self.shaders[material.shader]
    if not shader then
        return nil, "material " .. tostring(material.name) .. " requested unknown shader " .. tostring(material.shader)
    end
    if love.graphics.setMeshCullMode then
        love.graphics.setMeshCullMode(material.double_sided and "none" or "back")
    end
    love.graphics.setShader(shader)
    local uniforms = {
        { "u_view_projection", view_projection, true },
        { "u_model", entry.node.world_matrix, true },
        { "u_normal_matrix", Math3D.normalMatrixFromMat4(entry.node.world_matrix), true },
        { "u_camera_position", scene.camera.position },
        { "u_light_direction", scene.light.direction },
        { "u_light_color", scene.light.color },
        { "u_ambient_color", scene.light.ambient },
    }
    for _, uniform in ipairs(uniforms) do
        local ok, err = send(shader, uniform[1], uniform[2], uniform[3])
        if not ok then
            return nil, err
        end
    end
    local material_ok, material_err = material:apply(shader)
    if not material_ok then
        return nil, material_err
    end
    love.graphics.draw(entry.mesh.handle)
    return true
end

function Renderer:_renderScene(scene, width, height)
    local view_projection, camera_err = scene.camera:getViewProjectionMatrix(width / height)
    if not view_projection then
        return nil, camera_err
    end
    local opaque, transparent = {}, {}
    renderable_lists(scene.root, true, opaque, transparent)
    love.graphics.setDepthMode("less", true)
    if love.graphics.setFrontFaceWinding then
        love.graphics.setFrontFaceWinding("ccw")
    end
    for _, entry in ipairs(opaque) do
        local ok, err = self:_drawRenderable(entry, scene, view_projection)
        if not ok then
            return nil, err
        end
    end
    -- Transparent assets retain authoring order. Scene scripts may create a
    -- dedicated order when a different painter's ordering is needed.
    love.graphics.setDepthMode("lequal", false)
    for _, entry in ipairs(transparent) do
        local ok, err = self:_drawRenderable(entry, scene, view_projection)
        if not ok then
            return nil, err
        end
    end
    return true
end

function Renderer:_composite(scene, options, target_canvas, width, height)
    if options.present == false then
        return true
    end
    love.graphics.setCanvas(target_canvas)
    love.graphics.origin()
    love.graphics.setDepthMode("always", false)
    if love.graphics.setMeshCullMode then
        love.graphics.setMeshCullMode("none")
    end
    if love.graphics.setFrontFaceWinding then
        love.graphics.setFrontFaceWinding("ccw")
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    if options.composite ~= false then
        local shader = self.shaders.composite
        love.graphics.setShader(shader)
        local fog = options.fog or {}
        local fog_source = fog.color or { 0, 0, 0 }
        local fog_color = { fog_source[1] or 0, fog_source[2] or 0, fog_source[3] or 0 }
        local fog_strength = fog.strength or 0
        local vignette = options.vignette or 0
        local sent, send_err = send(shader, "u_fog_color", fog_color)
        if not sent then return nil, send_err end
        sent, send_err = send(shader, "u_fog_strength", fog_strength)
        if not sent then return nil, send_err end
        sent, send_err = send(shader, "u_vignette", vignette)
        if not sent then return nil, send_err end
    else
        love.graphics.setShader()
    end
    local x = tonumber(options.x) or 0
    local y = tonumber(options.y) or 0
    local output_width = tonumber(options.output_width) or width
    local output_height = tonumber(options.output_height) or height
    love.graphics.draw(self.color, x, y, 0, output_width / width, output_height / height)
    return true
end

--- Renders to the library's color/depth pair and composites the color Canvas.
function Renderer:draw(scene, options)
    if self.released then
        return nil, "renderer has been released"
    end
    options = options or {}
    if type(options) ~= "table" then
        return nil, "draw options must be a table"
    end
    if not graphics_ready() then
        return nil, "love.graphics is not active"
    end
    local width = tonumber(options.width or scene.width)
    local height = tonumber(options.height or scene.height)
    if width or height then
        width, height = math.floor(width or 0), math.floor(height or 0)
        if width < 1 or height < 1 then
            return nil, "draw width and height must both be positive"
        end
    else
        width, height = canvas_dimensions()
    end
    local shader_ok, shader_err = self:_ensureShaders()
    if not shader_ok then
        return nil, shader_err
    end
    local target_ok, target_err = self:_ensureTargets(width, height, options)
    if not target_ok then
        return nil, target_err
    end

    local special_state = Capabilities.captureSpecialState()
    local target_canvas = love.graphics.getCanvas()
    local pushed = false
    local ok, result_or_err = xpcall(function()
        love.graphics.push("all")
        pushed = true
        love.graphics.origin()
        love.graphics.setScissor()
        love.graphics.setCanvas({ self.color, depthstencil = self.depth })
        local clear = options.clear_color or scene.clear_color
        -- LÖVE clears color, stencil, then depth in this overload.
        love.graphics.clear(clear[1], clear[2], clear[3], clear[4], 0, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha")
        local rendered, render_err = self:_renderScene(scene, width, height)
        if not rendered then
            error(render_err, 0)
        end
        local composited, composite_err = self:_composite(scene, options, target_canvas, width, height)
        if not composited then
            error(composite_err, 0)
        end
        return self.color
    end, function(err)
        return tostring(err)
    end)
    if pushed then
        pcall(love.graphics.pop)
    end
    -- Kristal's graphics stack does not retain every render-target detail.
    -- Reapply the caller's color target even when the render pass failed.
    pcall(love.graphics.setCanvas, target_canvas)
    Capabilities.restoreSpecialState(special_state)
    if not ok then
        return nil, "ddd-3d render failed: " .. tostring(result_or_err)
    end
    return result_or_err
end

function Renderer:getCanvas()
    return self.color
end

function Renderer:release()
    if self.released then
        return true
    end
    Capabilities.releaseCanvasPair(self.pair)
    self.pair = nil
    self.color = nil
    self.depth = nil
    if self.shaders then
        for _, shader in pairs(self.shaders) do
            release_if_possible(shader)
        end
    end
    self.shaders = nil
    self.released = true
    return true
end

return Renderer
