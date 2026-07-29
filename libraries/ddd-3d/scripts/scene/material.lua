local Material = {}
Material.__index = Material

local function color(value, fallback)
    value = value or fallback
    return {
        tonumber(value[1]) or 1,
        tonumber(value[2]) or 1,
        tonumber(value[3]) or 1,
        tonumber(value[4]) == nil and 1 or tonumber(value[4]),
    }
end

local function vec3(value, fallback)
    value = value or fallback
    return {
        tonumber(value[1]) or 0,
        tonumber(value[2]) or 0,
        tonumber(value[3]) or 0,
    }
end

local function send(shader, name, value, layout)
    if shader.hasUniform then
        local checked, has_uniform = pcall(shader.hasUniform, shader, name)
        if checked and not has_uniform then
            return true
        end
    end
    local ok, err
    if layout then
        ok, err = pcall(shader.send, shader, name, value, layout)
    else
        ok, err = pcall(shader.send, shader, name, value)
    end
    if not ok then
        return nil, "could not send shader uniform " .. name .. ": " .. tostring(err)
    end
    return true
end

function Material.new(options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, "material options must be a table"
    end
    local alpha_mode = options.alpha_mode or options.alphaMode or "OPAQUE"
    if alpha_mode ~= "OPAQUE" and alpha_mode ~= "MASK" and alpha_mode ~= "BLEND" then
        return nil, "unsupported material alpha mode: " .. tostring(alpha_mode)
    end
    return setmetatable({
        name = options.name or "material",
        shader = options.shader or "lit",
        base_color = color(options.base_color or options.baseColor, { 1, 1, 1, 1 }),
        emissive = vec3(options.emissive, { 0, 0, 0 }),
        metallic = math.max(0, math.min(1, tonumber(options.metallic) or 0)),
        roughness = math.max(0.04, math.min(1, tonumber(options.roughness) or 0.75)),
        alpha_mode = alpha_mode,
        alpha_cutoff = tonumber(options.alpha_cutoff or options.alphaCutoff) or 0.5,
        double_sided = options.double_sided == true or options.doubleSided == true,
        texture = options.texture,
        released = false,
    }, Material)
end

function Material:clone(overrides)
    overrides = overrides or {}
    overrides.name = overrides.name or self.name
    overrides.shader = overrides.shader or self.shader
    overrides.base_color = overrides.base_color or self.base_color
    overrides.emissive = overrides.emissive or self.emissive
    if overrides.metallic == nil then overrides.metallic = self.metallic end
    if overrides.roughness == nil then overrides.roughness = self.roughness end
    overrides.alpha_mode = overrides.alpha_mode or self.alpha_mode
    if overrides.alpha_cutoff == nil then overrides.alpha_cutoff = self.alpha_cutoff end
    if overrides.double_sided == nil then overrides.double_sided = self.double_sided end
    overrides.texture = overrides.texture or self.texture
    return Material.new(overrides)
end

function Material:apply(shader)
    if self.released then
        return nil, "material has been released"
    end
    if not shader then
        return nil, "material shader is unavailable"
    end
    local sends = {
        { "u_base_color", self.base_color },
        { "u_emissive", self.emissive },
        { "u_metallic", self.metallic },
        { "u_roughness", self.roughness },
        { "u_alpha_cutoff", self.alpha_cutoff },
        { "u_alpha_mask", self.alpha_mode == "MASK" and 1 or 0 },
    }
    for _, uniform in ipairs(sends) do
        local ok, err = send(shader, uniform[1], uniform[2])
        if not ok then
            return nil, err
        end
    end
    return true
end

function Material:release()
    self.released = true
    return true
end

return Material
