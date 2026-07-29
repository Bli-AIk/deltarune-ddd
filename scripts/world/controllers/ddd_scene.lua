-- Thin Kristal adapter for data-only ddd-3d presets.
local DDDScene, super = Class(Event, "ddd_scene")

local function warn(message)
    if Kristal and Kristal.Console and Kristal.Console.warn then
        Kristal.Console:warn(message)
    else
        print(message)
    end
end

local function valid_identifier(value)
    return type(value) == "string" and value:match("^[%w_/-]+$") ~= nil
end

local function valid_relative_path(value)
    return type(value) == "string"
        and value ~= ""
        and value:sub(1, 1) ~= "/"
        and not value:find("..", 1, true)
end

function DDDScene:init(data)
    super.init(self, data)
    self.runtime = nil
    self.disabled = false
    self.failure_reported = false
end

function DDDScene:_disable(reason)
    self.disabled = true
    self:release()
    if not self.failure_reported then
        self.failure_reported = true
        warn("ddd-3d disabled for this map: " .. tostring(reason))
    end
end

function DDDScene:_context()
    local properties = (self.data and self.data.properties) or {}
    local asset_root = properties["asset_root"]
    if not valid_relative_path(asset_root) then
        return nil, "controller property asset_root must be a safe relative path"
    end
    if not Mod or not Mod.info or type(Mod.info.path) ~= "string" then
        return nil, "Kristal mod path is unavailable"
    end
    return {
        asset_root = Mod.info.path .. "/" .. asset_root,
        output = {
            width = SCREEN_WIDTH,
            height = SCREEN_HEIGHT,
        },
    }
end

function DDDScene:_loadRuntime()
    local properties = (self.data and self.data.properties) or {}
    local scene_id = properties["scene"]
    if not valid_identifier(scene_id) then
        return nil, "controller property scene must be a preset identifier"
    end
    local library = Mod and Mod.libs and Mod.libs["ddd-3d"]
    if not library or type(library.newRuntime) ~= "function" then
        return nil, "ddd-3d library is unavailable"
    end
    local loaded, definition_or_err = pcall(modRequire, "scripts.scenes." .. scene_id)
    if not loaded then
        return nil, "could not load scene preset: " .. tostring(definition_or_err)
    end
    local context, context_err = self:_context()
    if not context then
        return nil, context_err
    end
    local runtime, runtime_err = library.newRuntime(definition_or_err, context)
    if not runtime then
        return nil, runtime_err
    end
    self.library = library
    self.context = context
    return runtime
end

function DDDScene:_worldContext()
    if not self.library or type(self.library.captureWorldContext) ~= "function" then
        return nil, "ddd-3d world-context support is unavailable"
    end
    return self.library.captureWorldContext(self.world, { include_effects = false })
end

function DDDScene:onLoad()
    if self.disabled or self.runtime then
        return
    end
    local runtime, err = self:_loadRuntime()
    if not runtime then
        self:_disable(err)
        return
    end
    self.runtime = runtime
end

function DDDScene:update()
    super.update(self)
    if self.disabled or not self.runtime then
        return
    end
    local world_context, context_err = self:_worldContext()
    if not world_context then
        self:_disable(context_err)
        return
    end
    local updated, err = self.runtime:update(DT, world_context)
    if not updated then
        self:_disable(err)
    end
end

function DDDScene:draw()
    if not self.disabled and self.runtime then
        local _, err = self.runtime:draw(self.context.output)
        if err then
            self:_disable(err)
        end
    end
    super.draw(self)
end

function DDDScene:release()
    if not self.runtime then
        return true
    end
    local runtime = self.runtime
    self.runtime = nil
    self.library = nil
    local released, err = runtime:release()
    if not released then
        return nil, err
    end
    return true
end

function DDDScene:onRemoveFromStage(stage)
    self:release()
    super.onRemoveFromStage(self, stage)
end

function DDDScene:onRemove(parent)
    self:release()
    super.onRemove(self, parent)
end

return DDDScene
