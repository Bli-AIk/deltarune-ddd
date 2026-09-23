local ROOT = "."

local function new_libraries()
    return {
        ["kristalI18n"] = {},
        ["magical-glass"] = {
            alias = "mgr",
        },
        ["undertale_monsters_recreation"] = {
            alias = "umr",
            dependencies = {"magical-glass"},
        },
        ["unrelated-library"] = {
            optionalDependencies = {"magical-glass"},
        },
    }
end

-- LuaJIT has no os.setenv, so the launch override is driven by stubbing the
-- reader for the duration of one load. The override also prints a summary line,
-- which is captured so the test output stays readable and the summary assertable.
local real_getenv = os.getenv
local real_print = print

local function run_selection(selection, spec)
    _G.HookSystem = {hook = function() end}
    _G.Map = {}
    _G.NPC = {}
    _G.Mod = {
        info = {
            optionalLibraries = selection,
            libs = new_libraries(),
            lib_order = {
                "kristalI18n",
                "magical-glass",
                "undertale_monsters_recreation",
                "unrelated-library",
            },
        },
    }

    os.getenv = function(name)
        if name == "DELTARUNE_DDD_CH1_OPTIONAL_LIBS" then
            return spec
        end
        return real_getenv(name)
    end

    local printed = {}
    print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do
            parts[#parts + 1] = tostring((select(index, ...)))
        end
        printed[#printed + 1] = table.concat(parts, " ")
    end

    local ok, result = pcall(function()
        assert(loadfile(ROOT .. "/mod.lua"))()
    end)
    print = real_print
    os.getenv = real_getenv

    if not ok then
        error(result, 0)
    end
    return Mod.info, printed
end

local function expect_present(info, id)
    assert(info.libs[id], "expected library to remain: " .. id)
end

local function expect_absent(info, id)
    assert(not info.libs[id], "expected library to be removed: " .. id)
end

local function expect_order(info, expected)
    assert(#info.lib_order == #expected, "unexpected library order length")
    for index, id in ipairs(expected) do
        assert(info.lib_order[index] == id, "unexpected library order at " .. index)
    end
end

local info = run_selection({
    ["magical-glass"] = true,
    ["undertale_monsters_recreation"] = true,
})
expect_present(info, "magical-glass")
expect_present(info, "undertale_monsters_recreation")
expect_present(info, "unrelated-library")

info = run_selection({
    ["magical-glass"] = true,
    ["undertale_monsters_recreation"] = false,
})
expect_present(info, "magical-glass")
expect_absent(info, "undertale_monsters_recreation")
expect_present(info, "unrelated-library")
expect_order(info, {"kristalI18n", "magical-glass", "unrelated-library"})

info = run_selection({
    ["magical-glass"] = false,
    ["undertale_monsters_recreation"] = true,
})
expect_absent(info, "magical-glass")
expect_absent(info, "undertale_monsters_recreation")
expect_present(info, "unrelated-library")
expect_order(info, {"kristalI18n", "unrelated-library"})

info = run_selection({
    ["missing-disabled-library"] = false,
})
expect_present(info, "magical-glass")
expect_present(info, "undertale_monsters_recreation")

local ok, message = pcall(run_selection, {
    ["missing-enabled-library"] = true,
})
assert(not ok and message:find("enabled optional library is missing", 1, true))

-- Launch-time override, driven through DELTARUNE_DDD_CH1_OPTIONAL_LIBS. Names
-- resolve against every library, not just the ones optionalLibraries lists.

-- A bare name and a "+" prefix both force a library on.
info = run_selection({["magical-glass"] = false}, "mgr")
expect_present(info, "magical-glass")

info = run_selection({["magical-glass"] = false}, "+mgr")
expect_present(info, "magical-glass")

-- Several entries at once; libraries the override does not mention keep their
-- mod.json value.
info = run_selection({["magical-glass"] = false}, "mgr,umr")
expect_present(info, "magical-glass")
expect_present(info, "undertale_monsters_recreation")

-- Turning on a dependent pulls in the dependency it requires, even though
-- mod.json has that dependency off. The summary reports both.
info, printed = run_selection({["magical-glass"] = false}, "umr")
expect_present(info, "magical-glass")
expect_present(info, "undertale_monsters_recreation")
expect_order(info, {
    "kristalI18n",
    "magical-glass",
    "undertale_monsters_recreation",
    "unrelated-library",
})
assert(#printed == 1, "expected exactly one override summary line")
assert(printed[1]:find("magical-glass=on", 1, true), printed[1])
assert(printed[1]:find("undertale_monsters_recreation=on", 1, true), printed[1])

-- "-" forces a library off.
info = run_selection({
    ["magical-glass"] = true,
    ["undertale_monsters_recreation"] = true,
}, "-umr")
expect_present(info, "magical-glass")
expect_absent(info, "undertale_monsters_recreation")
expect_order(info, {"kristalI18n", "magical-glass", "unrelated-library"})

-- Turning off a library still removes the dependents that require it.
info = run_selection({
    ["magical-glass"] = true,
    ["undertale_monsters_recreation"] = true,
}, "-mgr")
expect_absent(info, "magical-glass")
expect_absent(info, "undertale_monsters_recreation")

-- Any library is addressable, not just the optional pair.
info = run_selection({}, "-kristalI18n")
expect_absent(info, "kristalI18n")
expect_present(info, "unrelated-library")
expect_order(info, {"magical-glass", "undertale_monsters_recreation", "unrelated-library"})

-- Full ids work for libraries that declare no alias.
info = run_selection({["magical-glass"] = false}, "undertale_monsters_recreation")
expect_present(info, "magical-glass")
expect_present(info, "undertale_monsters_recreation")

-- An override cannot require a library and disable it in the same breath.
ok, message = pcall(run_selection, {["magical-glass"] = false}, "umr,-mgr")
assert(not ok and message:find("requires disabled library", 1, true), message)

-- Unknown names fail loudly and list every valid name, alias included.
-- This is stricter than the mod.json path, where an unknown disabled id is ignored.
ok, message = pcall(run_selection, {}, "mg")
assert(not ok and message:find("valid names:", 1, true), message)
assert(message:find("magical-glass (mgr)", 1, true), message)
assert(message:find("undertale_monsters_recreation (umr)", 1, true), message)

-- A blank spec is the same as no override at all.
info, printed = run_selection({
    ["magical-glass"] = false,
    ["undertale_monsters_recreation"] = true,
}, "   ")
expect_absent(info, "magical-glass")
expect_absent(info, "undertale_monsters_recreation")
assert(#printed == 0, "a blank override must not print a summary")

print("optional library selection: PASS")
