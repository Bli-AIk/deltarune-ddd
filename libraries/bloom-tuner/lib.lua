local LIB_ID = "bloom-tuner"
local suit = Mod and Mod.libs and Mod.libs["love-suit"]
local PANEL_WIDTH = 342
local PANEL_HEIGHT = 440
local PANEL_MARGIN = 14

local lib = {
    enabled = false,
    visible = false,
    runtime = nil,
    values = nil,
    defaults = nil,
    enabled_state = nil,
    copy_status = nil,
    cursor_forced = false,
    cursor_was_visible = nil,
}

local function config(key)
    return Kristal.getLibConfig(LIB_ID, key)
end

local function dev_mode()
    return not Kristal.isDevMode or Kristal.isDevMode()
end

local function copy_bloom(source)
    source = type(source) == "table" and source or {}
    return {
        threshold = tonumber(source.threshold) or 0.16,
        soft_knee = tonumber(source.soft_knee) or 0.10,
        strength = tonumber(source.strength) or 1.0,
        radius = tonumber(source.radius) or 1.5,
        scale = tonumber(source.scale) or 0.50,
        tint = {
            tonumber(source.tint and source.tint[1]) or 0.62,
            tonumber(source.tint and source.tint[2]) or 0.24,
            tonumber(source.tint and source.tint[3]) or 1.0,
        },
    }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clamp_values(values)
    values.threshold = clamp(values.threshold, 0, 1)
    values.soft_knee = clamp(values.soft_knee, 0, 1)
    values.strength = clamp(values.strength, 0, 3)
    values.radius = clamp(values.radius, 0, 4)
    values.scale = clamp(values.scale, 0.25, 0.75)
    for index = 1, 3 do
        values.tint[index] = clamp(values.tint[index], 0, 1)
    end
end

local function panel_bounds()
    local width, height = love.graphics.getDimensions()
    return PANEL_MARGIN,
        PANEL_MARGIN,
        math.max(0, math.min(PANEL_WIDTH, width - PANEL_MARGIN * 2)),
        math.max(0, math.min(PANEL_HEIGHT, height - PANEL_MARGIN * 2))
end

local function pointer_in_panel(self)
    if not self.enabled or not self.visible or not self.runtime or not love.mouse then
        return false
    end
    local x, y = love.mouse.getPosition()
    local panel_x, panel_y, panel_width, panel_height = panel_bounds()
    return x >= panel_x and x <= panel_x + panel_width
        and y >= panel_y and y <= panel_y + panel_height
end

local function is_ui_target(self)
    return self.enabled and self.visible and self.suit
        and (self.suit.anyHovered() or self.suit.anyActive())
end

function lib:update_cursor()
    if not love.mouse or not love.mouse.setVisible then
        return
    end

    if pointer_in_panel(self) then
        if not self.cursor_forced then
            self.cursor_was_visible = love.mouse.isVisible and love.mouse.isVisible() or false
            love.mouse.setVisible(true)
            self.cursor_forced = true
        end
    elseif self.cursor_forced then
        love.mouse.setVisible(self.cursor_was_visible == true)
        self.cursor_forced = false
        self.cursor_was_visible = nil
    end
end

local function label_options()
    return {
        align = "left",
        color = {
            normal = { fg = { 0.92, 0.92, 0.96 } },
        },
    }
end

local function draw_label(self, text, width)
    self.suit.Label(text, label_options(), self.suit.layout:row(width or 306, 15))
end

local function read_field(values, field)
    local tint_index = field:match("^tint%[(%d+)%]$")
    if tint_index then
        return values.tint[tonumber(tint_index)]
    end
    return values[field]
end

local function write_field(values, field, value)
    local tint_index = field:match("^tint%[(%d+)%]$")
    if tint_index then
        values.tint[tonumber(tint_index)] = value
    else
        values[field] = value
    end
end

local function draw_slider(self, id, label, field, minimum, maximum, format)
    local values = self.values
    local value = read_field(values, field)
    draw_label(self, string.format("%s: " .. format, label, value))
    local slider_info = {
        value = value,
        min = minimum,
        max = maximum,
        step = (maximum - minimum) / 100,
    }
    local result = self.suit.Slider(slider_info, {
        id = id,
    }, self.suit.layout:row(306, 17))
    if result.changed then
        write_field(values, field, clamp(slider_info.value, minimum, maximum))
    end
end

local function apply_values(self)
    if not self.runtime or not self.runtime.output then
        return
    end
    clamp_values(self.values)
    self.runtime.output.bloom = self.enabled_state and self.values or false
end

local function lua_config(values)
    return string.format(
        "bloom = { threshold = %.3f, soft_knee = %.3f, strength = %.3f, radius = %.3f, scale = %.3f, tint = { %.3f, %.3f, %.3f } },",
        values.threshold,
        values.soft_knee,
        values.strength,
        values.radius,
        values.scale,
        values.tint[1],
        values.tint[2],
        values.tint[3]
    )
end

function lib:init()
    self.enabled = config("enabled") ~= false
        and (config("only_dev") == false or dev_mode())
    self.suit = self.enabled and suit or nil
    if not self.enabled or not self.suit or not HookSystem then
        return
    end

    local toggle_key = config("toggle_key") or "f10"
    HookSystem.hook(love, "draw", function(orig, ...)
        local result = orig(...)
        self:update_cursor()
        if self.runtime and self.visible then
            love.graphics.push("all")
            love.graphics.origin()
            self:draw()
            love.graphics.pop()
        end
        return result
    end)

    HookSystem.hook(love, "keypressed", function(orig, key, is_repeat, ...)
        if self.visible and key == toggle_key and not is_repeat then
            self.visible = false
            self:update_cursor()
            return
        elseif not self.visible and key == toggle_key and not is_repeat and self.runtime then
            self.visible = true
            self:update_cursor()
            return
        end
        if self.visible and self.suit.anyActive() then
            self.suit.keypressed(key)
            return
        end
        if self.visible then
            self.suit.keypressed(key)
        end
        return orig(key, is_repeat, ...)
    end)

    HookSystem.hook(love, "mousepressed", function(orig, x, y, button, ...)
        if is_ui_target(self) then
            return
        end
        return orig(x, y, button, ...)
    end)

    HookSystem.hook(love, "mousereleased", function(orig, x, y, button, ...)
        if is_ui_target(self) then
            return
        end
        return orig(x, y, button, ...)
    end)

    HookSystem.hook(love, "wheelmoved", function(orig, x, y, ...)
        if is_ui_target(self) then
            return
        end
        return orig(x, y, ...)
    end)
end

function lib:attach(runtime)
    if not self.enabled or not runtime then
        return
    end
    self.runtime = runtime
    self.values = copy_bloom(runtime.output and runtime.output.bloom)
    self.defaults = copy_bloom(self.values)
    self.enabled_state = not (runtime.output and runtime.output.bloom == false)
    self.visible = config("show_on_attach") == true
    apply_values(self)
end

function lib:detach(runtime)
    if runtime == nil or self.runtime == runtime then
        self.runtime = nil
        self:update_cursor()
        self.values = nil
        self.defaults = nil
        self.enabled_state = nil
        self.copy_status = nil
    end
end

function lib:postUpdate()
    if self.runtime and self.visible and self.suit then
        self.suit.enterFrame()
    end
end

function lib:draw()
    if not self.runtime or not self.values or not self.suit then
        return
    end

    local x, y, panel_width, panel_height = panel_bounds()

    love.graphics.setColor(0.025, 0.018, 0.055, 0.96)
    love.graphics.rectangle("fill", x, y, panel_width, panel_height, 6, 6)
    love.graphics.setColor(0.38, 0.26, 0.72, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, panel_width, panel_height, 6, 6)

    if not self.font then
        self.font = love.graphics.newFont(12)
    end
    love.graphics.setFont(self.font)
    self.suit.layout:reset(x + 12, y + 10)
    self.suit.layout:padding(2, 2)
    draw_label(self, "Bloom tuner  [F10 to hide]", panel_width - 24)

    local checkbox = {
        checked = self.enabled_state,
        text = "Bloom enabled",
    }
    local checkbox_result = self.suit.Checkbox(
        checkbox,
        { id = "bloom_tuner_enabled" },
        self.suit.layout:row(panel_width - 24, 18)
    )
    if checkbox_result.hit then
        self.enabled_state = checkbox.checked
        apply_values(self)
    end

    if self.enabled_state then
        draw_slider(self, "bloom_threshold", "Threshold", "threshold", 0, 1, "%.2f")
        draw_slider(self, "bloom_soft_knee", "Soft knee", "soft_knee", 0, 1, "%.2f")
        draw_slider(self, "bloom_strength", "Strength", "strength", 0, 3, "%.2f")
        draw_slider(self, "bloom_radius", "Radius", "radius", 0, 4, "%.2f")
        draw_slider(self, "bloom_scale", "Scale", "scale", 0.25, 0.75, "%.2f")
        draw_slider(self, "bloom_tint_r", "Tint R", "tint[1]", 0, 1, "%.2f")
        draw_slider(self, "bloom_tint_g", "Tint G", "tint[2]", 0, 1, "%.2f")
        draw_slider(self, "bloom_tint_b", "Tint B", "tint[3]", 0, 1, "%.2f")
    else
        draw_label(self, "Bloom disabled", panel_width - 24)
    end

    local reset = self.suit.Button("Reset", {
        id = "bloom_tuner_reset",
        color = {
            normal = { bg = { 0.20, 0.14, 0.38 }, fg = { 1, 1, 1 } },
            hovered = { bg = { 0.32, 0.22, 0.58 }, fg = { 1, 1, 1 } },
            active = { bg = { 0.46, 0.30, 0.76 }, fg = { 1, 1, 1 } },
        },
    }, self.suit.layout:row(98, 20))
    if reset.hit then
        self.values = copy_bloom(self.defaults)
        self.enabled_state = true
        apply_values(self)
    end

    local copy_button = self.suit.Button("Copy Lua", {
        id = "bloom_tuner_copy",
        color = {
            normal = { bg = { 0.16, 0.20, 0.34 }, fg = { 1, 1, 1 } },
            hovered = { bg = { 0.24, 0.32, 0.52 }, fg = { 1, 1, 1 } },
            active = { bg = { 0.30, 0.42, 0.66 }, fg = { 1, 1, 1 } },
        },
    }, self.suit.layout:row(98, 20))
    if copy_button.hit then
        love.system.setClipboardText(lua_config(self.values))
        self.copy_status = "Copied bloom config"
    end
    if self.copy_status then
        self.suit.Label(self.copy_status, label_options(), self.suit.layout:row(panel_width - 24, 15))
    end

    apply_values(self)
    self.suit.draw()
end

function lib:cleanup()
    self:detach()
end

if Registry and Registry.registerGlobal then
    Registry.registerGlobal("BloomTuner", lib)
end

return lib
