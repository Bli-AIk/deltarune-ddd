local function mapNameKey(id)
    return "map_" .. tostring(id):gsub("[^%w_]", "_") .. "_name"
end

local POWER_STAT_LABELS = {
    ["Guts:"] = "guts_stat",
    ["Rudeness"] = "rudeness_stat",
    ["Fluffiness"] = "fluffiness_stat",
    ["Coldness"] = "coldness_stat",
    ["Boldness"] = "boldness_stat",
}

local ITEM_BONUS_NAMES = {
    ["GrazeTime"] = "graze_time_bonus",
}

local NOELLE_SPECIAL_TITLE_KEYS = {
    ["Ice Trancer"] = "chara_noelle_title_ice_trancer",
    ["Frostmancer"] = "chara_noelle_title_frostmancer",
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

local function hookItemBonusNames()
    HookSystem.hook(Item, "getBonusName", function(orig, item, ...)
        local bonus_name = orig(item, ...)
        if Game:getLanguage() ~= "zh_hans" then
            return bonus_name
        end

        local key = ITEM_BONUS_NAMES[bonus_name]
        return key and Game:loc(bonus_name, key) or bonus_name
    end)
end

local function localizeVictoryText(text)
    if Game:getLanguage() ~= "zh_hans" or type(text) ~= "string" then
        return text
    end

    local xp, money, currency = text:match("^%* You won!\n%* Got (.-) EXP and (.-) (.-)%.$")
    if xp then
        return Game:loc("* You won!\n* Got [var:xp] EXP and [var:money] [var:currency].", "battle_victory_with_exp", {
            xp = xp,
            money = money,
            currency = currency,
        })
    end

    local stronger_money, stronger_currency, stronger = text:match("^%* You won!\n%* Got (.-) (.-)%.\n%* (.-) became stronger%.$")
    if stronger_money then
        if stronger == "You" then
            stronger = "你"
        end
        return Game:loc("* You won!\n* Got [var:money] [var:currency].\n* [var:stronger] became stronger.", "battle_victory_stronger", {
            money = stronger_money,
            currency = stronger_currency,
            stronger = stronger,
        })
    end

    return text
end

local function hookVictoryText()
    HookSystem.hook(Battle, "battleText", function(orig, battle, text, ...)
        return orig(battle, localizeVictoryText(text), ...)
    end)
end

local function hookNoelleTitle()
    local noelle = Registry.getPartyMember("noelle")
    if not noelle then return end

    HookSystem.hook(noelle, "getTitle", function(orig, self, ...)
        local title = orig(self, ...)
        if Game:getLanguage() ~= "zh_hans" then
            return title
        end

        for english_title, key in pairs(NOELLE_SPECIAL_TITLE_KEYS) do
            if title:find(english_title, 1, true) then
                return Game:loc("LV[var:lv] [var:title]", "chara_getTitle", {
                    lv = self:getLevel(),
                    title = Game:loc(title:gsub("^LV%d+ ", ""), key),
                })
            end
        end
        return title
    end)
end

local function hookFrozenEnemyText()
    HookSystem.hook(Interactable, "onInteract", function(orig, self, ...)
        if type(self.text) == "table" and self.text[1] == "* (It's frozen solid...)" then
            self.text_id = self.text_id or {}
            self.text_id[1] = "frozen_enemy_text"
        end
        return orig(self, ...)
    end)
end

function Mod:init()
    hookItemBonusNames()
    hookVictoryText()
    hookNoelleTitle()
    hookFrozenEnemyText()

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
