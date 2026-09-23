local function module_factory(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk()
end

local old_game, old_registry = _G.Game, _G.Registry
_G.Game = {
    chapter = 2,
    langStr = {
        item_alpha_name_chapter_2 = "Alpha",
        item_alpha_description = "Alpha description",
        item_beta_name_chapter_2 = "Beta",
    },
    langBaseStr = {},
}
_G.Registry = {
    items = {
        alpha = function()
            return {
                id = "alpha",
                name = "Alpha",
                use_name = "Use Alpha",
                description = "Alpha description",
            }
        end,
        beta = function()
            return { id = "beta", name = "Shared" }
        end,
        gamma = function()
            return { id = "gamma", name = "Shared" }
        end,
    },
}

local ctx = {
    library = {},
    constants = {
        DEFAULT_LANGUAGE = "en",
        FALLBACK_LANGUAGE = "en",
        DEFAULT_LANGUAGE_TOGGLE_KEY = "f7",
    },
    runtime = {},
    system_language = {},
    cjk = {},
    data = {},
    assets = {},
    hooks = {},
}
ctx.text = module_factory("libraries/kristal-i18n/modules/text.lua")(ctx)
local i18n = module_factory("libraries/kristal-i18n/modules/lifecycle.lua")(ctx)

local function expect(value, field, preferred_id, expected_key, expected_id)
    local key, id = i18n:getItemTextLocalizationKey(value, field, preferred_id)
    assert(key == expected_key, "unexpected localization key")
    assert(id == expected_id, "unexpected item id")
end

expect("Alpha", "name", nil, "item_alpha_name_chapter_2", "alpha")
expect("Use Alpha", "name", nil, "item_alpha_name_chapter_2", "alpha")
expect("Alpha description", "description", nil, "item_alpha_description", "alpha")
expect("Shared", "name", "beta", "item_beta_name_chapter_2", "beta")
assert(i18n:getItemTextLocalizationKey("Use Alpha", "description") == nil)
assert(i18n:getItemTextLocalizationKey("unknown", "name") == nil)
assert(i18n:getItemTextLocalizationKey({}, "name") == nil)

_G.Game, _G.Registry = old_game, old_registry
print("i18n item key API: PASS")
