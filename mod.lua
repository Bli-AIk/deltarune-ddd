local function mapNameKey(id)
    return "map_" .. tostring(id):gsub("[^%w_]", "_") .. "_name"
end

local POWER_STAT_LABELS = {
    ["Guts:"] = "guts_stat",
    ["Rudeness"] = "rudeness_stat",
    ["Fluffiness"] = "fluffiness_stat",
}

local function hookPowerStatLabels(party_member)
    if not party_member then return end

    HookSystem.hook(party_member, "drawPowerStat", function(orig, self, index, x, y, menu)
        if Game:getLanguage() ~= "zh_hans" then
            return orig(self, index, x, y, menu)
        end

        local original_print = love.graphics.print
        love.graphics.print = function(text, ...)
            local key = POWER_STAT_LABELS[text]
            if key then
                text = Game:loc(text, key)
            end
            return original_print(text, ...)
        end

        local ok, result = xpcall(function()
            return orig(self, index, x, y, menu)
        end, debug.traceback)
        love.graphics.print = original_print

        if not ok then
            error(result)
        end
        return result
    end)
end

function Mod:init()
    for _, id in ipairs({"kris", "susie", "ralsei", "noelle"}) do
        hookPowerStatLabels(Registry.getPartyMember(id))
    end

    Game:registerEvent("squeak", function(data)
        return Squeak(data.x, data.y, {data.width, data.height, data.polygon})
    end)
    print(Game:loc("Loaded [var:name]!", "mod.loaded", {name = self.info.name}))
end

function Mod:updateMapName()
    if Game.world and Game.world.map and Game.world.map.id and Game.loc then
        local map = Game.world.map
        local properties = (map.data and map.data.properties) or {}
        local name_key = properties["name_id"] or mapNameKey(map.id)
        local default_name = properties["name"] or map.name or map.id
        map.name = Game:loc(default_name, name_key)
    end
end

function Mod:updateBattleLocalization()
    if Game.battle then
        for _, enemy in ipairs(Game.battle.enemies or {}) do
            if enemy.applyLocalization then
                enemy:applyLocalization(true)
            end
        end
    end
end

function Mod:postUpdate()
    self:updateMapName()
end

function Mod:onKeyPressed(key, is_repeat)
    -- F6 is reserved by Kristal for debug rendering.
    if is_repeat or key ~= "f7" or not Game.setLanguage then
        return
    end

    local next_language = Game:getLanguage() == "zh_hans" and "en" or "zh_hans"
    if Game:setLanguage(next_language) then
        self:updateMapName()
        self:updateBattleLocalization()

        local message = Game:loc("* Language switched to [var:language].", "mod.language_switched", {
            language = Game:getLanguageName()
        })
        print(message)

        if Game.world and Game.world.player and not Game.world:hasCutscene() and not Game.world.menu then
            Game.world:showText(message)
        end

        return true
    end
end
