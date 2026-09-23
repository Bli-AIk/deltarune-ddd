-- The library enable messages get translated by re-running
-- localizeConsoleSegments over the console history.
--
-- Libraries announce themselves at init(), which is before kristal-i18n
-- installs its Console:push hook, so the lines sit in the console history in
-- English. refreshConsoleStartupHistory() rewrites the whole history at
-- postInit (and on every language change), and that pass is what turns
-- "[System] [INFO] Enabled library X." into the localized line.
--
-- This loads the real kristal-i18n modules without the engine and drives that
-- pass over a history shaped exactly like the engine's Logger produces, so
-- the matcher, the lang lookup and the segment rewrite are all covered.
--
-- Run from the project root:
--   luajit tests/i18n_console_segments.lua

local ROOT = "libraries/kristal-i18n"

local captured_ctx
_G.libRequire = function(_, module_path)
    local factory = assert(loadfile(ROOT .. "/" .. module_path:gsub("%.", "/") .. ".lua"))()
    return function(ctx)
        captured_ctx = captured_ctx or ctx
        return factory(ctx)
    end
end

_G.ACTIVE_LIB = { info = { id = "kristalI18n" } }
_G.Mod = { info = { id = "deltarune-ddd-ch1", config = {} }, libs = {} }
_G.Game = {}
_G.SCREEN_WIDTH = 640
-- Mirrors src/engine/vars.lua: console markup resolves color names through the
-- engine's COLORS global, which does not exist outside the engine.
_G.COLORS = {
    orange = { 1, 0.625, 0.25, 1 },
    white = { 1, 1, 1, 1 },
}

assert(loadfile(ROOT .. "/lib.lua"))()

local text = captured_ctx.text
assert(type(text.localizeConsoleSegments) == "function")
assert(type(text.refreshConsoleStartupHistory) == "function")

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    end
end

-- Renders a segment array as "<r,g,b,a>text<r,g,b,a>text" so a whole line can be
-- asserted in one comparison.
local function describe(segments)
    local out = {}
    for _, part in ipairs(segments) do
        if type(part) == "table" then
            out[#out + 1] = "<" .. table.concat(part, ",") .. ">"
        else
            out[#out + 1] = tostring(part)
        end
    end
    return table.concat(out)
end

-- Pulls a single flat key out of a lang file. The naive whole-file reader used
-- elsewhere chokes on the escaped quotes these files contain, and only these
-- keys matter here.
local function lang_value(path, key)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return assert(source:match('"' .. key .. '"%s*:%s*"([^"]*)"'), key .. " missing from " .. path)
end

local WELCOME = "Welcome to KRISTAL! This is the debug console."
local HINT = "You can enter Lua here to be ran! Use help() to open the help menu."

-- The console history's shape: a segment array where a table switches the
-- color from that point on, exactly like ConsoleOutputListener builds it.
local function announce_line(message)
    return {
        { 0.5, 1, 1, 1 },
        "[System]",
        { 1, 1, 1, 1 },
        " ",
        { 0.5, 1, 0.5, 1 },
        "[INFO]",
        { 1, 1, 1, 1 },
        " " .. message,
    }
end

-- Runs one refresh over a fresh history and returns it.
local function refresh(language)
    local console = {
        history = {
            { WELCOME },
            { HINT },
            announce_line("Enabled library magical-glass."),
            announce_line("Enabled library terminal-cli."),
        },
        -- The engine wraps to the console width; one line is enough here.
        getWrappedLines = function(_, wrapped)
            return nil, { wrapped }
        end,
    }
    _G.Kristal = { Console = console }

    Game.langStr = {
        console_welcome = lang_value(ROOT .. "/lang/" .. language .. ".json", "console_welcome"),
        console_lua_hint = lang_value(ROOT .. "/lang/" .. language .. ".json", "console_lua_hint"),
        console_logger_library_enabled = lang_value(
            ROOT .. "/lang/" .. language .. ".json",
            "console_logger_library_enabled"
        ),
    }
    Game.langBaseStr = {
        console_welcome = WELCOME,
        console_lua_hint = HINT,
        console_logger_library_enabled = lang_value(ROOT .. "/lang/en.json", "console_logger_library_enabled"),
    }
    Game.lang = language

    text.refreshConsoleStartupHistory()
    return console.history
end

-- 1. Chinese: the "[System] [INFO] " prefix keeps the Logger's own colors
--    (cyan tag, green level), the message is replaced, and only the library
--    name is highlighted.
local zh = refresh("zh_hans")
check(
    "zh_hans: only the prefix keeps the Logger colors",
    describe(zh[3]) == "<0.5,1,1,1>[System]<1,1,1,1> <0.5,1,0.5,1>[INFO]<1,1,1,1> "
        .. "已启用 <1,0.625,0.25,1>magical-glass<1,1,1,1> 库。",
    describe(zh[3])
)
check(
    "zh_hans: second line translated too",
    describe(zh[4]):find("已启用 <1,0.625,0.25,1>terminal-cli<1,1,1,1> 库。", 1, true) ~= nil,
    describe(zh[4])
)

-- 2. English: same shape, and the plain text is exactly what the libraries
--    emit, so switching languages cannot silently drop or double the prefix.
local en = refresh("en")
check(
    "en: highlights the name the same way",
    describe(en[3]) == "<0.5,1,1,1>[System]<1,1,1,1> <0.5,1,0.5,1>[INFO]<1,1,1,1> "
        .. "Enabled library <1,0.625,0.25,1>magical-glass<1,1,1,1>.",
    describe(en[3])
)

-- 3. The rest of the history is left alone.
check("zh_hans: unrelated lines untouched", zh[1] ~= nil)

if failures > 0 then
    print(("\n%d check(s) failed"):format(failures))
    os.exit(1)
end

print("\nall checks passed")
