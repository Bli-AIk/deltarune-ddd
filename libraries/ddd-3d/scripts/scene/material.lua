local Material = {}
Material.__index = Material

local TEXTURE_FIELDS = {
    base_color_texture = {
        "base_color_texture",
        "baseColorTexture",
        "albedo_texture",
        "albedoTexture",
        "base_color_map",
        "baseColorMap",
        "albedo_map",
        "albedoMap",
        -- `texture` predates PBR maps and remains a base-color alias for
        -- direct API consumers that already use it.
        "texture",
    },
    normal_texture = {
        "normal_texture",
        "normalTexture",
        "normal_map",
        "normalMap",
    },
    roughness_texture = {
        "roughness_texture",
        "roughnessTexture",
        "roughness_map",
        "roughnessMap",
    },
}

local NORMAL_STRENGTH_FIELDS = { "normal_strength", "normalStrength", "normal_scale", "normalScale" }
local UV_SCALE_FIELDS = { "uv_scale", "uvScale" }

local function clamped_number(value, fallback, minimum, maximum)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(minimum, math.min(maximum, value))
end

local function parse_hex_color(value, channels)
    if type(value) ~= "string" then
        return nil
    end
    local hex = value
    if hex:sub(1, 1) == "#" then
        hex = hex:sub(2)
    end
    if not hex:match("^%x+$") then
        return nil
    end
    if #hex == 3 or #hex == 4 then
        local expanded = {}
        for index = 1, #hex do
            local digit = hex:sub(index, index)
            expanded[#expanded + 1] = digit .. digit
        end
        hex = table.concat(expanded)
    elseif #hex ~= 6 and #hex ~= 8 then
        return nil
    end

    local result = {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
    if channels == 4 then
        result[4] = (#hex == 8 and tonumber(hex:sub(7, 8), 16) / 255) or 1
    end
    return result
end

local function color(value, fallback)
    if type(value) == "string" then
        local parsed = parse_hex_color(value, 4)
        if not parsed then
            return nil, "color must be a hex string such as #RRGGBB or #RRGGBBAA"
        end
        return parsed
    end
    value = value or fallback
    if type(value) ~= "table" then
        return nil, "color must be a color table or hex string"
    end
    return {
        tonumber(value[1]) or 1,
        tonumber(value[2]) or 1,
        tonumber(value[3]) or 1,
        tonumber(value[4]) == nil and 1 or tonumber(value[4]),
    }
end

local function vec3(value, fallback)
    if type(value) == "string" then
        local parsed = parse_hex_color(value, 3)
        if not parsed then
            return nil, "color must be a hex string such as #RRGGBB"
        end
        return parsed
    end
    value = value or fallback
    if type(value) ~= "table" then
        return nil, "color must be a color table or hex string"
    end
    return {
        tonumber(value[1]) or 0,
        tonumber(value[2]) or 0,
        tonumber(value[3]) or 0,
    }
end

local function vec2(value, fallback)
    value = value or fallback
    return {
        tonumber(value[1]) or fallback[1],
        tonumber(value[2]) or fallback[2],
    }
end

local function option_value(options, names)
    for _, name in ipairs(names) do
        if options[name] ~= nil then
            return options[name]
        end
    end
    return nil
end

local function texture_source(value, field)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        if value == "" then
            return nil, field .. " must not be an empty path"
        end
        return value
    end
    -- The direct API may pass a LÖVE Image or Canvas. Declarative runtime
    -- definitions are stricter and only accept strings (see Runtime).
    if type(value) == "userdata" then
        return value
    end
    if type(value) == "table" and (type(value.typeOf) == "function" or type(value.getDimensions) == "function") then
        return value
    end
    return nil, field .. " must be an image resource or a non-empty path"
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
    local uv_scale = option_value(options, UV_SCALE_FIELDS)
    if uv_scale ~= nil and type(uv_scale) ~= "table" then
        return nil, "uv_scale must be a vec2 table"
    end
    local base_color_texture, texture_err = texture_source(
        option_value(options, TEXTURE_FIELDS.base_color_texture),
        "base_color_texture"
    )
    if texture_err then return nil, texture_err end
    local normal_texture
    normal_texture, texture_err = texture_source(
        option_value(options, TEXTURE_FIELDS.normal_texture),
        "normal_texture"
    )
    if texture_err then return nil, texture_err end
    local roughness_texture
    roughness_texture, texture_err = texture_source(
        option_value(options, TEXTURE_FIELDS.roughness_texture),
        "roughness_texture"
    )
    if texture_err then return nil, texture_err end
    local base_color, base_color_err = color(options.base_color or options.baseColor, { 1, 1, 1, 1 })
    if not base_color then
        return nil, "base_color: " .. tostring(base_color_err)
    end
    local emissive, emissive_err = vec3(options.emissive, { 0, 0, 0 })
    if not emissive then
        return nil, "emissive: " .. tostring(emissive_err)
    end
    return setmetatable({
        name = options.name or "material",
        shader = options.shader or "lit",
        base_color = base_color,
        emissive = emissive,
        metallic = clamped_number(options.metallic, 0, 0, 1),
        roughness = clamped_number(options.roughness, 0.75, 0.04, 1),
        specular_strength = clamped_number(
            options.specular_strength or options.specularStrength,
            1,
            0,
            1
        ),
        ambient_reflection = clamped_number(
            options.ambient_reflection or options.ambientReflection,
            0.8,
            0,
            1
        ),
        normal_strength = clamped_number(option_value(options, NORMAL_STRENGTH_FIELDS), 1, 0, 4),
        uv_scale = vec2(uv_scale, { 1, 1 }),
        alpha_mode = alpha_mode,
        alpha_cutoff = clamped_number(options.alpha_cutoff or options.alphaCutoff, 0.5, 0, 1),
        double_sided = options.double_sided == true or options.doubleSided == true,
        base_color_texture = base_color_texture,
        texture = base_color_texture,
        normal_texture = normal_texture,
        roughness_texture = roughness_texture,
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
    if overrides.specular_strength == nil and overrides.specularStrength == nil then
        overrides.specular_strength = self.specular_strength
    end
    if overrides.ambient_reflection == nil and overrides.ambientReflection == nil then
        overrides.ambient_reflection = self.ambient_reflection
    end
    if option_value(overrides, NORMAL_STRENGTH_FIELDS) == nil then
        overrides.normal_strength = self.normal_strength
    end
    if option_value(overrides, UV_SCALE_FIELDS) == nil then
        overrides.uv_scale = self.uv_scale
    end
    overrides.alpha_mode = overrides.alpha_mode or self.alpha_mode
    if overrides.alpha_cutoff == nil then overrides.alpha_cutoff = self.alpha_cutoff end
    if overrides.double_sided == nil then overrides.double_sided = self.double_sided end
    if option_value(overrides, TEXTURE_FIELDS.base_color_texture) == nil then
        overrides.base_color_texture = self.base_color_texture
    end
    if option_value(overrides, TEXTURE_FIELDS.normal_texture) == nil then
        overrides.normal_texture = self.normal_texture
    end
    if option_value(overrides, TEXTURE_FIELDS.roughness_texture) == nil then
        overrides.roughness_texture = self.roughness_texture
    end
    return Material.new(overrides)
end

--- Returns a copy with string texture paths resolved by `resolve`.
--- This intentionally leaves direct Image/Canvas values untouched.
---@param options table
---@param resolve fun(path: string): string?
---@return table? options
---@return string? err
function Material.resolveTexturePaths(options, resolve)
    if type(options) ~= "table" then
        return nil, "material options must be a table"
    end
    if type(resolve) ~= "function" then
        return nil, "texture path resolver must be a function"
    end
    local resolved = {}
    for key, value in pairs(options) do
        resolved[key] = value
    end
    for canonical, names in pairs(TEXTURE_FIELDS) do
        local source = option_value(options, names)
        if type(source) == "string" then
            local path, err = resolve(source)
            if type(path) ~= "string" or path == "" then
                return nil, err or (canonical .. " could not be resolved")
            end
            resolved[canonical] = path
        elseif source ~= nil then
            resolved[canonical] = source
        end
    end
    return resolved
end

--- Validates material texture fields in a data-only runtime definition.
---@param options table
---@return boolean? ok
---@return string? field
---@return string? err
function Material.validateTexturePaths(options)
    if type(options) ~= "table" then
        return nil, nil, "material options must be a table"
    end
    for _, names in pairs(TEXTURE_FIELDS) do
        for _, name in ipairs(names) do
            local value = options[name]
            if value ~= nil and (type(value) ~= "string" or value == "") then
                return nil, name, "must be a non-empty texture path"
            end
        end
    end
    for _, name in ipairs(NORMAL_STRENGTH_FIELDS) do
        local value = options[name]
        if value ~= nil and type(value) ~= "number" then
            return nil, name, "must be a finite number"
        end
    end
    for _, name in ipairs(UV_SCALE_FIELDS) do
        local value = options[name]
        if value ~= nil then
            if type(value) ~= "table" or type(value[1]) ~= "number" or type(value[2]) ~= "number" then
                return nil, name, "must be a vec2 table"
            end
        end
    end
    return true
end

--- Returns whether value uses one of the supported hex color formats.
---@param value any
---@return boolean
function Material.isHexColor(value)
    return parse_hex_color(value, 4) ~= nil
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
        { "u_specular_strength", self.specular_strength },
        { "u_ambient_reflection", self.ambient_reflection },
        { "u_normal_strength", self.normal_strength },
        { "u_uv_scale", self.uv_scale },
        { "u_double_sided", self.double_sided and 1 or 0 },
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
