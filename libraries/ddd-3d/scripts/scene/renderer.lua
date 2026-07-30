local LIB_ID = "ddd-3d"
local Capabilities = libRequire(LIB_ID, "scripts.core.capabilities")
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")

local Renderer = {}
Renderer.__index = Renderer

local shader_names = {
    "lit",
    "emissive",
    "composite",
    "bloom_extract",
    "bloom_blur",
}

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

local function configure_texture(texture)
    if texture and texture.setFilter then
        pcall(texture.setFilter, texture, "linear", "linear")
    end
    if texture and texture.setMipmapFilter then
        pcall(texture.setMipmapFilter, texture, "linear", 0)
    end
    if texture and texture.setWrap then
        pcall(texture.setWrap, texture, "repeat", "repeat")
    end
    return texture
end

local function is_absolute_path(path)
    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function file_data_for_path(path)
    if not is_absolute_path(path) then
        return path
    end
    if not love.filesystem or not love.filesystem.newFileData then
        return nil, "LÖVE FileData support is unavailable"
    end
    -- LÖVE's image loader reads virtual paths only. Runtime asset roots are
    -- deliberately allowed to be absolute so Kristal can point at a mod's
    -- authored 3D directory; bridge those files through FileData instead.
    local contents = read_text(path)
    if not contents then
        return nil, "could not read texture file " .. path
    end
    local ok, file_data = pcall(love.filesystem.newFileData, contents, path)
    if not ok then
        return nil, "could not create texture FileData for " .. path .. ": " .. tostring(file_data)
    end
    return file_data
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

local function linear_determinant(matrix)
    local a00, a01, a02 = matrix[1], matrix[5], matrix[9]
    local a10, a11, a12 = matrix[2], matrix[6], matrix[10]
    local a20, a21, a22 = matrix[3], matrix[7], matrix[11]
    return a00 * (a11 * a22 - a12 * a21)
        - a01 * (a10 * a22 - a12 * a20)
        + a02 * (a10 * a21 - a11 * a20)
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
        texture_cache = {},
        fallback_textures = nil,
        bloom_a = nil,
        bloom_b = nil,
        bloom_width = nil,
        bloom_height = nil,
        bloom_unavailable = false,
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

local function release_canvas(canvas)
    if canvas and canvas.release then
        pcall(canvas.release, canvas)
    end
end

function Renderer:_ensureBloomTargets(width, height, options)
    if self.bloom_unavailable then
        return nil, "bloom canvases are unavailable"
    end
    local bloom = options.bloom or {}
    local scale = tonumber(bloom.scale) or 0.5
    scale = math.max(0.25, math.min(0.75, scale))
    local bloom_width = math.max(1, math.floor(width * scale + 0.5))
    local bloom_height = math.max(1, math.floor(height * scale + 0.5))
    if self.bloom_a
        and self.bloom_b
        and self.bloom_width == bloom_width
        and self.bloom_height == bloom_height
    then
        return true
    end
    if not self.pair or not self.pair.color_format then
        return nil, "bloom requires an initialized color canvas"
    end
    local settings = { format = self.pair.color_format }
    local ok_a, bloom_a = pcall(love.graphics.newCanvas, bloom_width, bloom_height, settings)
    if not ok_a then
        self.bloom_unavailable = true
        return nil, tostring(bloom_a)
    end
    local ok_b, bloom_b = pcall(love.graphics.newCanvas, bloom_width, bloom_height, settings)
    if not ok_b then
        release_canvas(bloom_a)
        self.bloom_unavailable = true
        return nil, tostring(bloom_b)
    end
    bloom_a:setFilter("linear", "linear")
    bloom_b:setFilter("linear", "linear")
    release_canvas(self.bloom_a)
    release_canvas(self.bloom_b)
    self.bloom_a = bloom_a
    self.bloom_b = bloom_b
    self.bloom_width = bloom_width
    self.bloom_height = bloom_height
    return true
end

function Renderer:_renderBloom(options, width, height)
    local bloom = options.bloom
    if bloom == false or type(bloom) ~= "table" then
        return false
    end
    local strength = tonumber(bloom.strength) or 0
    if strength <= 0 then
        return false
    end
    local targets_ok = self:_ensureBloomTargets(width, height, options)
    if not targets_ok then
        return false
    end
    local bloom_width, bloom_height = self.bloom_width, self.bloom_height
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setDepthMode("always", false)
    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setCanvas(self.bloom_a)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(self.shaders.bloom_extract)
    send(self.shaders.bloom_extract, "u_threshold", tonumber(bloom.threshold) or 0.35)
    send(self.shaders.bloom_extract, "u_soft_knee", tonumber(bloom.soft_knee) or 0.16)
    love.graphics.draw(self.color, 0, 0, 0, bloom_width / width, bloom_height / height)

    local blur_shader = self.shaders.bloom_blur
    love.graphics.setCanvas(self.bloom_b)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(blur_shader)
    send(blur_shader, "u_direction", { 1 / bloom_width, 0 })
    send(blur_shader, "u_radius", tonumber(bloom.radius) or 1.0)
    love.graphics.draw(self.bloom_a)

    love.graphics.setCanvas(self.bloom_a)
    love.graphics.clear(0, 0, 0, 0)
    send(blur_shader, "u_direction", { 0, 1 / bloom_height })
    love.graphics.draw(self.bloom_b)
    love.graphics.setShader()
    love.graphics.pop()
    return true
end

local function texture_cache_key(path, semantic)
    return semantic .. "\0" .. path
end

function Renderer:_loadTexture(path, semantic)
    if type(path) ~= "string" or path == "" then
        return nil, "texture path must be a non-empty string"
    end
    local key = texture_cache_key(path, semantic)
    local cached = self.texture_cache[key]
    if cached then
        if cached.error then
            return nil, cached.error
        end
        return cached.texture
    end
    if not graphics_ready() then
        local err = "love.graphics is not active"
        self.texture_cache[key] = { error = err }
        return nil, err
    end
    local settings = {
        -- LÖVE treats base-color maps as sRGB while normal and roughness maps
        -- must retain their raw linear data under gamma-correct rendering.
        linear = semantic ~= "base_color",
        mipmaps = true,
    }
    local source, source_err = file_data_for_path(path)
    if not source then
        local err = "could not load " .. semantic .. " texture " .. path .. ": " .. tostring(source_err)
        self.texture_cache[key] = { error = err }
        return nil, err
    end
    local ok, texture = pcall(love.graphics.newImage, source, settings)
    if not ok then
        local err = "could not load " .. semantic .. " texture " .. path .. ": " .. tostring(texture)
        self.texture_cache[key] = { error = err }
        return nil, err
    end
    self.texture_cache[key] = { texture = configure_texture(texture) }
    return self.texture_cache[key].texture
end

function Renderer:_ensureFallbackTextures()
    if self.fallback_textures then
        return self.fallback_textures
    end
    if not graphics_ready() or not love.image or not love.image.newImageData then
        return nil, "LÖVE ImageData support is unavailable"
    end
    local function solid_color(color, linear)
        local data = love.image.newImageData(1, 1)
        data:setPixel(0, 0, color[1], color[2], color[3], color[4])
        local ok, texture = pcall(love.graphics.newImage, data, {
            linear = linear,
            mipmaps = false,
        })
        if not ok then
            return nil, tostring(texture)
        end
        return configure_texture(texture)
    end
    local base_color, base_err = solid_color({ 1, 1, 1, 1 }, false)
    if not base_color then
        return nil, "could not create base-color fallback texture: " .. tostring(base_err)
    end
    local normal, normal_err = solid_color({ 0.5, 0.5, 1, 1 }, true)
    if not normal then
        release_if_possible(base_color)
        return nil, "could not create normal fallback texture: " .. tostring(normal_err)
    end
    local roughness, roughness_err = solid_color({ 1, 1, 1, 1 }, true)
    if not roughness then
        release_if_possible(base_color)
        release_if_possible(normal)
        return nil, "could not create roughness fallback texture: " .. tostring(roughness_err)
    end
    self.fallback_textures = {
        base_color = base_color,
        normal = normal,
        roughness = roughness,
    }
    return self.fallback_textures
end

function Renderer:_textureFor(source, semantic)
    if source == nil then
        return nil
    end
    if type(source) == "string" then
        return self:_loadTexture(source, semantic)
    end
    return source
end

function Renderer:_bindMaterialTextures(material, shader)
    if material.shader ~= "lit" then
        return true
    end
    local has_base_color = material.base_color_texture ~= nil
    local has_normal = material.normal_texture ~= nil
    local has_roughness = material.roughness_texture ~= nil
    local flags = {
        { "u_has_base_color_texture", has_base_color and 1 or 0 },
        { "u_has_normal_texture", has_normal and 1 or 0 },
        { "u_has_roughness_texture", has_roughness and 1 or 0 },
    }
    for _, uniform in ipairs(flags) do
        local ok, err = send(shader, uniform[1], uniform[2])
        if not ok then return nil, err end
    end
    if not has_base_color and not has_normal and not has_roughness then
        return true
    end

    local fallback, fallback_err = self:_ensureFallbackTextures()
    if not fallback then return nil, fallback_err end
    local base_color, base_err = self:_textureFor(material.base_color_texture, "base_color")
    if not base_color then base_color = fallback.base_color end
    if base_err then return nil, base_err end
    local normal, normal_err = self:_textureFor(material.normal_texture, "normal")
    if not normal then normal = fallback.normal end
    if normal_err then return nil, normal_err end
    local roughness, roughness_err = self:_textureFor(material.roughness_texture, "roughness")
    if not roughness then roughness = fallback.roughness end
    if roughness_err then return nil, roughness_err end

    for _, uniform in ipairs({
        { "u_base_color_texture", base_color },
        { "u_normal_texture", normal },
        { "u_roughness_texture", roughness },
    }) do
        local ok, err = send(shader, uniform[1], uniform[2])
        if not ok then return nil, err end
    end
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
    -- A Blender-native source conversion is reflective. Keep the GPU's
    -- front-facing result aligned with the transformed triangle winding for
    -- both culling and double-sided normal handling.
    if love.graphics.setFrontFaceWinding then
        local winding = linear_determinant(entry.node.world_matrix) < 0 and "cw" or "ccw"
        love.graphics.setFrontFaceWinding(winding)
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
        { "u_fill_light_direction", scene.light.fill.direction },
        { "u_fill_light_color", scene.light.fill.color },
        { "u_fill_light_strength", scene.light.fill.strength },
    }
    for index = 0, 3 do
        local point = scene.light.point_lights[index + 1] or {}
        local suffix = "_" .. tostring(index)
        uniforms[#uniforms + 1] = { "u_point_light_position" .. suffix, point.position or { 0, 0, 0 } }
        uniforms[#uniforms + 1] = { "u_point_light_color" .. suffix, point.color or { 0, 0, 0 } }
        uniforms[#uniforms + 1] = { "u_point_light_strength" .. suffix, point.strength or 0 }
        uniforms[#uniforms + 1] = { "u_point_light_range" .. suffix, point.range or 1 }
    end
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
    local texture_ok, texture_err = self:_bindMaterialTextures(material, shader)
    if not texture_ok then
        return nil, texture_err
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
        local bloom = options.bloom
        local bloom_enabled = self.bloom_a and type(bloom) == "table" and (tonumber(bloom.strength) or 0) > 0
        sent, send_err = send(shader, "u_bloom_enabled", bloom_enabled and 1 or 0)
        if not sent then return nil, send_err end
        if bloom_enabled then
            sent, send_err = send(shader, "u_bloom_texture", self.bloom_a)
            if not sent then return nil, send_err end
        end
        sent, send_err = send(shader, "u_bloom_strength", bloom_enabled and (tonumber(bloom.strength) or 0) or 0)
        if not sent then return nil, send_err end
        local tint = bloom and bloom.tint or { 0.72, 0.30, 1.0 }
        sent, send_err = send(shader, "u_bloom_tint", { tint[1] or 0, tint[2] or 0, tint[3] or 0 })
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
        self:_renderBloom(options, width, height)
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
    release_canvas(self.bloom_a)
    release_canvas(self.bloom_b)
    self.bloom_a = nil
    self.bloom_b = nil
    if self.shaders then
        for _, shader in pairs(self.shaders) do
            release_if_possible(shader)
        end
    end
    self.shaders = nil
    for _, cached in pairs(self.texture_cache or {}) do
        release_if_possible(cached.texture)
    end
    self.texture_cache = {}
    if self.fallback_textures then
        for _, texture in pairs(self.fallback_textures) do
            release_if_possible(texture)
        end
    end
    self.fallback_textures = nil
    self.released = true
    return true
end

return Renderer
