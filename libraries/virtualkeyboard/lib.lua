local lib = {}

local LIB_ID = "virtualkeyboard"

local function config(key)
    return Kristal.getLibConfig(LIB_ID, key)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function distance_squared(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function is_android()
    return love.system and love.system.getOS and love.system.getOS() == "Android"
end

local function get_number(key, default, minimum)
    local value = tonumber(config(key))
    if not value then
        return default
    end
    if minimum then
        value = math.max(minimum, value)
    end
    return value
end

local function button_layout()
    return {
        {key = "left", kind = "arrow", x = 32, y = 360},
        {key = "right", kind = "arrow", x = 192, y = 360},
        {key = "up", kind = "arrow", x = 112, y = 285},
        {key = "down", kind = "arrow", x = 112, y = 435},
        {key = "z", kind = "button", x = 520, y = 360},
        {key = "x", kind = "button", x = 600, y = 300},
        {key = "c", kind = "button", x = 600, y = 420}
    }
end

local function action_button_layout()
    return {
        {key = "z", kind = "button", x = 520, y = 360},
        {key = "x", kind = "button", x = 600, y = 300},
        {key = "c", kind = "button", x = 600, y = 420}
    }
end

local function direction_mapping(x, y, center_x, center_y, radius, deadzone)
    local dx = x - center_x
    local dy = y - center_y
    local threshold = radius * deadzone
    local mapping = {}

    -- Test each axis independently so a diagonal touch can hold two keys.
    if math.abs(dx) > threshold then
        mapping[dx < 0 and "left" or "right"] = true
    end
    if math.abs(dy) > threshold then
        mapping[dy < 0 and "up" or "down"] = true
    end
    return mapping
end

local function release_button(self, button)
    local touch_id = button.touch_id
    if touch_id == nil then
        return
    end

    button.touch_id = nil
    button.pressed = false
    self:set_source_keys(touch_id, {})

    local touch = self.touches[touch_id]
    if touch and touch.owner == button then
        touch.owner = nil
    end
end

local function reset_joystick(self)
    local joystick = self.joystick
    if not joystick then
        return
    end

    local touch_id = joystick.touch_id
    if touch_id ~= nil then
        self:set_source_keys(touch_id, {})
        local touch = self.touches[touch_id]
        if touch and touch.owner == joystick then
            touch.owner = nil
        end
    end

    joystick.touch_id = nil
    joystick.handle_x = joystick.x
    joystick.handle_y = joystick.y
    joystick.mapping = {}
end

function lib:emit_key(key, pressed)
    local was_pressed = self.virtual_keys[key] == true
    if was_pressed == pressed then
        return
    end

    self.virtual_keys[key] = pressed

    -- Feed Kristal directly so a touch is handled in the same event pass as a
    -- physical key. Fall back to LÖVE events when used outside Kristal.
    if Input and Input.onKeyPressed and Input.onKeyReleased then
        if pressed then
            Input.onKeyPressed(key, false)
        else
            Input.onKeyReleased(key)
        end
    elseif love.event then
        if pressed then
            love.event.push("keypressed", key, key, false)
        else
            love.event.push("keyreleased", key, key)
        end
    end
end

function lib:set_source_keys(source, keys)
    if source == nil then
        return
    end

    self.source_keys = self.source_keys or {}
    self.key_sources = self.key_sources or {}

    local previous = self.source_keys[source] or {}
    local next_keys = {}
    for key, active in pairs(keys or {}) do
        if active then
            next_keys[key] = true
        end
    end

    for key in pairs(previous) do
        if not next_keys[key] then
            local sources = self.key_sources[key]
            if sources then
                sources[source] = nil
                if next(sources) == nil then
                    self.key_sources[key] = nil
                    self:emit_key(key, false)
                end
            end
        end
    end

    for key in pairs(next_keys) do
        if not previous[key] then
            local sources = self.key_sources[key]
            local was_active = sources and next(sources) ~= nil
            if not sources then
                sources = {}
                self.key_sources[key] = sources
            end
            sources[source] = true
            if not was_active then
                self:emit_key(key, true)
            end
        end
    end

    if next(next_keys) == nil then
        self.source_keys[source] = nil
    else
        self.source_keys[source] = next_keys
    end
end

function lib:load_image(path)
    self.image_cache = self.image_cache or {}
    if self.image_cache[path] then
        return self.image_cache[path]
    end

    local full_path = self.info.path .. "/assets/" .. path
    local ok, image = pcall(love.graphics.newImage, full_path)
    if not ok then
        print("[virtualkeyboard] Could not load " .. full_path .. ": " .. tostring(image))
        return nil
    end

    image:setFilter("nearest", "nearest")
    self.image_cache[path] = image
    return image
end

function lib:make_button(data)
    local scale = get_number("button_scale", 2.5, 0.5)
    local normal_path = "buttons/" .. data.kind .. "-" .. data.key .. ".png"
    local pressed_path = "buttons/" .. data.kind .. "-" .. data.key .. "1.png"
    local normal = self:load_image(normal_path)
    local pressed = self:load_image(pressed_path)

    if not normal or not pressed then
        return nil
    end

    return {
        key = data.key,
        kind = data.kind,
        x = data.x,
        y = data.y,
        radius = get_number("button_radius", 38, 1),
        scale = scale,
        normal = normal,
        pressed_image = pressed,
        touch_id = nil,
        pressed = false
    }
end

function lib:build_layout()
    self.buttons = {}
    self.direction_pad = nil
    self.joystick = nil

    local layout = config("layout")
    if layout == "joystick" then
        local joystick_scale = get_number("joystick_scale", 2.5, 0.5)
        self.joystick = {
            kind = "joystick",
            x = 112,
            y = 360,
            radius = get_number("joystick_radius", 108, 1),
            max_radius = 54 * joystick_scale,
            deadzone = clamp(get_number("joystick_deadzone", 0.35, 0), 0, 0.95),
            scale = joystick_scale,
            container = self:load_image("joystick/joystick-container.png"),
            handle = self:load_image("joystick/joystick-handle.png"),
            touch_id = nil,
            handle_x = 112,
            handle_y = 360,
            mapping = {}
        }

        if not self.joystick.container or not self.joystick.handle then
            self.joystick = nil
        end

        for _, data in ipairs(action_button_layout()) do
            local button = self:make_button(data)
            if button then
                table.insert(self.buttons, button)
            end
        end
    else
        self.direction_pad = {
            kind = "direction_pad",
            x = 112,
            y = 360,
            radius = get_number("direction_area_radius", 122, 1),
            deadzone = clamp(get_number("direction_deadzone", 0.2, 0), 0, 0.95)
        }

        for _, data in ipairs(button_layout()) do
            local button = self:make_button(data)
            if button then
                table.insert(self.buttons, button)
            end
        end
    end
end

function lib:update_layout()
    local scale = Kristal.getGameScale()
    local offset_x, offset_y = Kristal.getSideOffsets()
    local screen_width = love.graphics.getWidth() / scale
    local side_width = offset_x / scale
    local game_top = offset_y / scale

    -- Use side areas when they are available. Narrow windows fall back to the
    -- 640x480 game canvas with the same edge spacing.
    self.screen_scale = scale
    self.side_layout = side_width >= 240

    local direction_center_x = 112
    local direction_center_y = 360
    local action_center_x = 560
    local action_center_y = 360
    local button_width = 0
    for _, button in ipairs(self.buttons) do
        button_width = math.max(
            button_width,
            button.normal:getWidth() * button.scale,
            button.pressed_image:getWidth() * button.scale
        )
    end

    if button_width > 0 then
        local layout_width = SCREEN_WIDTH or 640
        local left_margin = button_width
        local right_margin = button_width * 2
        if self.side_layout then
            layout_width = screen_width
        end

        direction_center_x = left_margin + button_width / 2 + 80
        action_center_x = layout_width - right_margin - button_width / 2 - 40
    elseif self.side_layout then
        direction_center_x = side_width / 2
        action_center_x = screen_width - side_width / 2
    end

    if self.side_layout then
        direction_center_y = game_top + direction_center_y
        action_center_y = game_top + action_center_y
    end

    if self.direction_pad then
        self.direction_pad.x = direction_center_x
        self.direction_pad.y = direction_center_y
    end
    if self.joystick then
        self.joystick.x = direction_center_x
        self.joystick.y = direction_center_y
        self.joystick.handle_x = direction_center_x
        self.joystick.handle_y = direction_center_y
        if self.joystick.touch_id ~= nil then
            self:update_joystick()
        end
    end

    for _, button in ipairs(self.buttons) do
        if button.kind == "arrow" then
            if button.key == "left" then
                button.x = direction_center_x - 80
                button.y = direction_center_y
            elseif button.key == "right" then
                button.x = direction_center_x + 80
                button.y = direction_center_y
            elseif button.key == "up" then
                button.x = direction_center_x
                button.y = direction_center_y - 75
            elseif button.key == "down" then
                button.x = direction_center_x
                button.y = direction_center_y + 75
            end
        elseif button.key == "z" then
            button.x = action_center_x - 40
            button.y = action_center_y
        elseif button.key == "x" then
            button.x = action_center_x + 40
            button.y = action_center_y - 60
        elseif button.key == "c" then
            button.x = action_center_x + 40
            button.y = action_center_y + 60
        end
    end
end

function lib:set_joystick_mapping(mapping)
    local joystick = self.joystick
    if not joystick then
        return
    end

    joystick.mapping = mapping
    self:set_source_keys(joystick.touch_id, mapping)
end

function lib:update_direction_touch(touch_id)
    local touch = self.touches[touch_id]
    local pad = self.direction_pad
    if not touch or not pad or touch.owner ~= pad then
        return
    end

    self:set_source_keys(touch_id, direction_mapping(
        touch.x,
        touch.y,
        pad.x,
        pad.y,
        pad.radius,
        pad.deadzone
    ))
end

function lib:update_joystick()
    local joystick = self.joystick
    if not joystick or joystick.touch_id == nil then
        return
    end

    local touch = self.touches[joystick.touch_id]
    if not touch then
        reset_joystick(self)
        return
    end

    local dx = touch.x - joystick.x
    local dy = touch.y - joystick.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local handle_distance = math.min(distance, joystick.max_radius)

    if distance > 0 then
        joystick.handle_x = joystick.x + (dx / distance) * handle_distance
        joystick.handle_y = joystick.y + (dy / distance) * handle_distance
    else
        joystick.handle_x = joystick.x
        joystick.handle_y = joystick.y
    end

    local mapping = {}
    if distance > joystick.radius * joystick.deadzone then
        local horizontal = math.abs(dx) / distance
        local vertical = math.abs(dy) / distance
        if math.abs(dx) > 0 and horizontal >= joystick.deadzone then
            mapping[dx < 0 and "left" or "right"] = true
        end
        if math.abs(dy) > 0 and vertical >= joystick.deadzone then
            mapping[dy < 0 and "up" or "down"] = true
        end
    end
    self:set_joystick_mapping(mapping)
end

function lib:screen_to_game(x, y)
    if Input and Input.getMousePosition then
        return Input.getMousePosition(x, y)
    end

    local scale = Kristal.getGameScale()
    local offset_x, offset_y = Kristal.getSideOffsets()
    return (x - offset_x) / scale, (y - offset_y) / scale
end

function lib:screen_to_control(x, y)
    self:update_layout()
    if self.side_layout then
        return x / self.screen_scale, y / self.screen_scale
    end
    return self:screen_to_game(x, y)
end

function lib:press_button(button, touch_id)
    if button.touch_id ~= nil then
        return false
    end

    button.touch_id = touch_id
    button.pressed = true
    self:set_source_keys(touch_id, {[button.key] = true})
    return true
end

function lib:assign_touch(touch_id, touch)
    if not self.visible or touch.owner then
        return false
    end

    if self.direction_pad and distance_squared(touch.x, touch.y, self.direction_pad.x, self.direction_pad.y)
        <= self.direction_pad.radius * self.direction_pad.radius then
        touch.owner = self.direction_pad
        self:update_direction_touch(touch_id)
        return true
    end

    if self.joystick and self.joystick.touch_id == nil
        and distance_squared(touch.x, touch.y, self.joystick.x, self.joystick.y)
            <= self.joystick.radius * self.joystick.radius then
        self.joystick.touch_id = touch_id
        touch.owner = self.joystick
        self:update_joystick()
        return true
    end

    for _, button in ipairs(self.buttons) do
        if distance_squared(touch.x, touch.y, button.x, button.y)
            <= button.radius * button.radius
            and self:press_button(button, touch_id) then
            touch.owner = button
            return true
        end
    end
    return false
end

function lib:touch_pressed(touch_id, x, y)
    local game_x, game_y = self:screen_to_control(x, y)
    local touch = {x = game_x, y = game_y, owner = nil}
    self.touches[touch_id] = touch
    self:assign_touch(touch_id, touch)
end

function lib:update_button_touch(touch_id, touch)
    local button = touch.owner
    if not button or button.touch_id ~= touch_id then
        touch.owner = nil
        self:assign_touch(touch_id, touch)
        return
    end

    if distance_squared(touch.x, touch.y, button.x, button.y)
        > button.radius * button.radius then
        release_button(self, button)
        self:assign_touch(touch_id, touch)
    end
end

function lib:touch_moved(touch_id, x, y)
    local touch = self.touches[touch_id]
    if not touch then
        return
    end

    touch.x, touch.y = self:screen_to_control(x, y)

    if touch.owner == self.direction_pad then
        self:update_direction_touch(touch_id)
    elseif touch.owner == self.joystick then
        self:update_joystick()
    elseif touch.owner then
        self:update_button_touch(touch_id, touch)
    else
        self:assign_touch(touch_id, touch)
    end
end

function lib:touch_released(touch_id, x, y)
    if self.touches[touch_id] then
        self:touch_moved(touch_id, x, y)
    end

    local touch = self.touches[touch_id]
    if not touch then
        return
    end

    if touch.owner == self.joystick then
        reset_joystick(self)
    elseif touch.owner and touch.owner.touch_id == touch_id then
        release_button(self, touch.owner)
    else
        self:set_source_keys(touch_id, {})
    end

    self.touches[touch_id] = nil
end

function lib:release_all()
    self.virtual_keys = self.virtual_keys or {}

    for _, button in ipairs(self.buttons or {}) do
        button.touch_id = nil
        button.pressed = false
    end
    if self.joystick then
        self.joystick.touch_id = nil
        self.joystick.handle_x = self.joystick.x
        self.joystick.handle_y = self.joystick.y
        self.joystick.mapping = {}
    end

    self.touches = {}
    self.source_keys = {}
    self.key_sources = {}
    local pressed_keys = {}
    for key, pressed in pairs(self.virtual_keys) do
        if pressed then
            table.insert(pressed_keys, key)
        end
    end
    for _, key in ipairs(pressed_keys) do
        self:emit_key(key, false)
    end
end

function lib:setVisible(visible)
    visible = visible == true
    if self.visible == visible then
        return self.visible
    end

    if not visible then
        self:release_all()
    end
    self.visible = visible
    return self.visible
end

function lib:isVisible()
    return self.enabled == true and self.visible == true
end

function lib:toggle()
    return self:setVisible(not self.visible)
end

function lib:install_hooks()
    if self.hooks_installed or not HookSystem then
        return
    end

    self.hooks_installed = true
    local owner = self

    if love.keyboard and type(love.keyboard.isDown) == "function" then
        HookSystem.hook(love.keyboard, "isDown", function(orig, key, ...)
            if owner.virtual_keys[key] then
                return true
            end
            return orig(key, ...)
        end)
    end

    HookSystem.hook(love, "touchpressed", function(orig, touch_id, x, y, dx, dy, pressure)
        local result = orig(touch_id, x, y, dx, dy, pressure)
        owner:touch_pressed(touch_id, x, y)
        return result
    end)

    HookSystem.hook(love, "touchmoved", function(orig, touch_id, x, y, dx, dy, pressure)
        local result = orig(touch_id, x, y, dx, dy, pressure)
        owner:touch_moved(touch_id, x, y)
        return result
    end)

    HookSystem.hook(love, "touchreleased", function(orig, touch_id, x, y, dx, dy, pressure)
        local result = orig(touch_id, x, y, dx, dy, pressure)
        owner:touch_released(touch_id, x, y)
        return result
    end)

    HookSystem.hook(love, "draw", function(orig, ...)
        local result = orig(...)
        owner:draw_overlay()
        return result
    end)

    HookSystem.hook(love, "focus", function(orig, focused, ...)
        local result = orig(focused, ...)
        if not focused then
            owner:release_all()
        end
        return result
    end)
end

function lib:onKeyPressed(key, is_repeat)
    local toggle_key = config("toggle_key")
    if self.enabled and not is_repeat and type(toggle_key) == "string"
        and toggle_key ~= "" and key == toggle_key then
        self:toggle()
        return true
    end
end

function lib:draw_controls(render_scale)
    local alpha = clamp(get_number("opacity", 0.78, 0), 0, 1)
    local joystick = self.joystick
    if joystick then
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(
            joystick.container,
            joystick.x * render_scale,
            joystick.y * render_scale,
            0,
            joystick.scale * render_scale,
            joystick.scale * render_scale,
            joystick.container:getWidth() / 2,
            joystick.container:getHeight() / 2
        )
        love.graphics.draw(
            joystick.handle,
            joystick.handle_x * render_scale,
            joystick.handle_y * render_scale,
            0,
            joystick.scale * render_scale,
            joystick.scale * render_scale,
            joystick.handle:getWidth() / 2,
            joystick.handle:getHeight() / 2
        )
    end

    for _, button in ipairs(self.buttons) do
        local pressed = button.touch_id ~= nil
        if button.kind == "arrow" then
            pressed = self.virtual_keys[button.key] == true
        end
        local image = pressed and button.pressed_image or button.normal
        love.graphics.setColor(1, 1, 1, pressed and math.min(1, alpha + 0.12) or alpha)
        love.graphics.draw(
            image,
            button.x * render_scale,
            button.y * render_scale,
            0,
            button.scale * render_scale,
            button.scale * render_scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    end
end

function lib:postDraw()
    if not self:isVisible() then
        return
    end

    self:update_layout()
    if self.side_layout then
        return
    end

    love.graphics.push("all")
    love.graphics.origin()
    self:draw_controls(1)
    love.graphics.pop()
end

function lib:draw_overlay()
    if not self:isVisible() or (Game and Kristal.getState() ~= Game) then
        return
    end

    self:update_layout()
    if not self.side_layout then
        return
    end

    love.graphics.push("all")
    love.graphics.origin()
    self:draw_controls(self.screen_scale)
    love.graphics.pop()
end

function lib:init()
    self.enabled = config("enabled") ~= false
        and (config("only_android") ~= true or is_android())
    self.visible = config("show_on_start") ~= false
    self.virtual_keys = {}
    self.source_keys = {}
    self.key_sources = {}
    self.touches = {}
    self.buttons = {}
    self.side_layout = false
    self.screen_scale = 1

    if not self.enabled then
        return
    end

    self:build_layout()
    self:update_layout()
    if #self.buttons == 0 and not self.joystick then
        self.enabled = false
        print("[virtualkeyboard] No controls could be loaded; library disabled")
        return
    end
    self:install_hooks()
end

function lib:unload()
    self:release_all()
    self.enabled = false
    self.visible = false
    self.buttons = {}
    self.direction_pad = nil
    self.joystick = nil
    self.image_cache = nil
end

function lib:cleanup()
    self:release_all()
end

if Registry and Registry.registerGlobal then
    Registry.registerGlobal("VirtualKeyboard", lib)
end

return lib
