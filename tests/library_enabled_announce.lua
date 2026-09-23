-- Every library announces itself with the same English line, and kristal-i18n
-- recognizes exactly that line to translate it.
--
-- The wording is a cross-repository contract: each library emits its own copy
-- (they are separate repositories and must keep working without kristal-i18n),
-- while the translation lives in kristal-i18n's localizeConsoleSegments. A
-- drifted literal in one library would silently stay untranslated, so this
-- test pins the wording, the matching pattern and both lang files together.
--
-- Run from the project root:
--   luajit tests/library_enabled_announce.lua

local ANNOUNCE = 'Logging.info("Enabled library "'

local ANNOUNCERS = {
    "libraries/kristal-i18n/modules/lifecycle.lua",
    "libraries/kristal-object-selector-plus/lib.lua",
    "libraries/kristal-debug-tools/lib.lua",
    "libraries/virtualkeyboard/lib.lua",
    "libraries/MagicalGlassRedux/lib.lua",
    "libraries/terminal-cli/lib.lua",
    "libraries/UndertaleMonstersRecreation/lib.lua",
}

-- Written out rather than assembled from ANNOUNCE: this is the shape the
-- pattern below is expected to match, not the shape the sources are read with.
-- The "[System] [INFO] " prefix comes from the engine's Logger; only MESSAGE is
-- the library's own text, and only MESSAGE is what the translation replaces.
local PREFIX = "[System] [INFO] "
local MESSAGE = "Enabled library magical-glass."
local ENGLISH = PREFIX .. MESSAGE

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    end
end

local function read_file(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local content = file:read("*a")
    file:close()
    return content
end

-- Flat key -> string reader: the lang files are flat maps.
local function read_lang(path)
    local out = {}
    for key, value in read_file(path):gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do
        out[key] = value
    end
    return out
end

for _, path in ipairs(ANNOUNCERS) do
    local file = io.open(path, "rb")
    if file then
        local source = file:read("*a")
        file:close()
        check(path .. " announces itself", source:find(ANNOUNCE, 1, true) ~= nil)
    end
end

-- The pattern is pulled out of the library rather than restated here, so this
-- test fails when the matcher is edited and the wording is not (or vice versa).
local text_source = read_file("libraries/kristal-i18n/modules/text.lua")
local pattern_literal = text_source:match('plain:match%("([^"]*Enabled library[^"]*)"%)')
check("kristal-i18n matches the announce line", pattern_literal ~= nil)

if not pattern_literal then
    print("\n1 check(s) failed")
    os.exit(1)
end

local pattern = assert(loadstring('return "' .. pattern_literal .. '"'))()
local prefix, captured = ENGLISH:match(pattern)
check("captured prefix is the Logger's tag", prefix == PREFIX, tostring(prefix))
check("captured name is the library id", captured == "magical-glass", tostring(captured))

local en = read_lang("libraries/kristal-i18n/lang/en.json")
local zh = read_lang("libraries/kristal-i18n/lang/zh_hans.json")
local key = "console_logger_library_enabled"

check("en.json defines " .. key, en[key] ~= nil)
check("zh_hans.json defines " .. key, zh[key] ~= nil)

-- The library name is the one highlighted part of the line; the surrounding
-- text has to stay uncolored, which is why the markup wraps only [var:name].
local HIGHLIGHT = "[color:orange][var:name][color:reset]"

if en[key] then
    -- The translation replaces only the message, so the template must not carry
    -- a prefix of its own; strip the markup and it has to be the emitted text.
    local rendered = en[key]:gsub("%[color:[^%]]*%]", ""):gsub("%[var:name%]", "magical-glass")
    check("english template round-trips to the emitted message", rendered == MESSAGE, rendered)
    check("english highlights the name", en[key]:find(HIGHLIGHT, 1, true) ~= nil, en[key])
end

if zh[key] then
    check("zh_hans translates the message", zh[key]:find("已启用 ", 1, true) == 1, zh[key])
    check("zh_hans leaves the prefix to the Logger", zh[key]:find("[System]", 1, true) == nil, zh[key])
    check("zh_hans highlights the name", zh[key]:find(HIGHLIGHT, 1, true) ~= nil, zh[key])
    check(
        "zh_hans substitutes the library name",
        zh[key]:gsub("%[var:name%]", "magical-glass"):find("magical-glass", 1, true) ~= nil,
        zh[key]
    )
end

if failures > 0 then
    print(("\n%d check(s) failed"):format(failures))
    os.exit(1)
end

print("\nall checks passed")
