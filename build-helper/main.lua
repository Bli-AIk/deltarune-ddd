-- Build helper for deltarune-ddd-ch1's packaging scripts, run with the LÖVE
-- the user already has (`love build-helper <subcommand> ...`). It is a
-- faithful Lua port of build_standalone.py, so the packaging needs no
-- Python — only LÖVE, which every user of the mod already needs to run it.
--
-- Subcommands (all positional args, like the python original):
--   patch-lua-config <stage_dir> <mod_id> <release_mode> <identity> <title>
--   patch-mod-manifest <manifest> <dev> <object_editor>
--   patch-android-properties <properties> <application_id> <name>
--       <orientation> <version_code> <version_name>
--   patch-android-local-properties <properties> <sdk_dir>
--   patch-android-gradle <gradle>
--   patch-android-game-activity <source>
--   patch-android-loading-touch <source>
--   set-mod-json-flag <manifest> <key> <true|false>
--   plan-release-libraries <stage_mod_dir> <plan_file>
--   zip-dir <output> <source> [prefix]

local Manifest = require("manifest")

local function fail(msg)
    io.stderr:write("build-helper: " .. tostring(msg) .. "\n")
    os.exit(1)
end

local function read_text(path)
    local f, err = io.open(path, "rb")
    if not f then fail("cannot read " .. path .. ": " .. tostring(err)) end
    local text = f:read("*a")
    f:close()
    -- Normalize CRLF to LF so literal block patches (patch-android-loading-touch,
    -- patch-android-game-activity, patch-android-gradle) match regardless of the
    -- checkout's line endings (Windows git may have checked files out as CRLF).
    return (text:gsub("\r\n", "\n"))
end

local function write_text(path, text)
    local f, err = io.open(path, "wb")
    if not f then fail("cannot write " .. path .. ": " .. tostring(err)) end
    f:write(text)
    f:close()
end

local function lua_quote(value)
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- Replace the first match; error when the pattern did not match at all,
-- mirroring python's re.subn(count=1) + count check.
local function replace_once(text, pattern, replacement, path)
    local patched, count = text:gsub(pattern, replacement, 1)
    if count ~= 1 then
        fail(string.format("Could not patch %q in %s", pattern, path))
    end
    return patched
end

-- Replace a literal block once (python's str.replace(original, repl, 1)).
local function replace_block(text, original, replacement, path)
    local start = text:find(original, 1, true)
    if not start then
        fail("Could not patch " .. path)
    end
    return text:sub(1, start - 1) .. replacement .. text:sub(start + #original)
end

-- Split on newlines (a trailing empty segment is preserved via the
-- text .. "\n" trick) and re-join with "\n".
local function each_line(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function join_lines(lines)
    return table.concat(lines, "\n")
end

-- Gradle properties helpers (python's set_gradle_property + removals).

local function set_gradle_property(text, key, value, path)
    if value:find("[\r\n]") then
        fail("Invalid newline in Gradle property '" .. key .. "' for " .. path)
    end
    local lines = each_line(text)
    local replaced = false
    for i, line in ipairs(lines) do
        if not replaced and line:sub(1, #key + 1) == key .. "=" then
            lines[i] = key .. "=" .. value
            replaced = true
        end
    end
    local result = join_lines(lines)
    if not replaced then
        if result ~= "" and result:sub(-1) ~= "\n" then
            result = result .. "\n"
        end
        result = result .. key .. "=" .. value .. "\n"
    end
    return result
end

-- Remove every line that starts (allowing leading whitespace) with key=.
local function remove_property_lines(text, key)
    local lines = each_line(text)
    local out = {}
    for _, line in ipairs(lines) do
        if not line:match("^[ \t]*" .. key:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "[ \t]*=") then
            out[#out + 1] = line
        end
    end
    return join_lines(out)
end

-- local.properties path escaping (java.util.Properties).
local function local_properties_value(value)
    return value:gsub("\\", "\\\\"):gsub(" ", "\\ "):gsub(":", "\\:"):gsub("=", "\\=")
end

local function is_ascii(value)
    for i = 1, #value do
        if value:byte(i) > 127 then
            return false
        end
    end
    return true
end

-- --- subcommands -----------------------------------------------------------

local function patch_lua_config(args)
    local stage_dir = args[2]
    local vendcust = stage_dir .. "/src/engine/vendcust.lua"
    local conf = stage_dir .. "/conf.lua"

    local text = read_text(vendcust)
    text = replace_once(text, "TARGET_MOD%s*=%s*[^\r\n]*", "TARGET_MOD = " .. lua_quote(args[3]), vendcust)
    text = replace_once(text, "AUTO_MOD_START%s*=%s*[^\r\n]*", "AUTO_MOD_START = true", vendcust)
    text = replace_once(text, "RELEASE_MODE%s*=%s*[^\r\n]*", "RELEASE_MODE = " .. args[4], vendcust)
    write_text(vendcust, text)

    text = read_text(conf)
    text = replace_once(text, "(%s*t%.identity%s*=%s*)[^\r\n]*", "%1" .. lua_quote(args[5]), conf)
    text = replace_once(text, "(%s*t%.window%.title%s*=%s*)[^\r\n]*", "%1" .. lua_quote(args[6]), conf)
    write_text(conf, text)
end

local function patch_mod_manifest(args)
    local manifest = args[2]
    local text = read_text(manifest)
    -- Lua patterns have no alternation; the value is matched up to the
    -- next comma/brace/newline, which is exactly what python's
    -- (true|false) captured here.
    text = replace_once(text, '("dev"%s*:%s*)[^,%}\r\n]*', "%1" .. args[3], manifest)
    text = replace_once(
        text,
        '("kristal%-object%-selector%-plus"%s*:%s*%{.-"enabled"%s*:%s*)[^,%}\r\n]*',
        "%1" .. args[4],
        manifest
    )
    write_text(manifest, text)
end

-- Set a top-level mod.json boolean flag (e.g. setWindowTitleAndIcon) in place,
-- preserving all JSONC comments and other fields. The value is matched up to
-- the next comma/brace/newline, so the previous value may be null/true/false.
-- If the key is absent the step is skipped with a warning (builds must not
-- hard-fail over an optional cosmetic flag).
local function set_mod_json_flag(args)
    local manifest = args[2]
    local key = args[3]
    local value = args[4]
    if value ~= "true" and value ~= "false" then
        fail("set-mod-json-flag: expected true or false, got " .. tostring(value))
    end
    if key == "" or key:find('"') then
        fail("set-mod-json-flag: invalid key " .. tostring(key))
    end
    local text = read_text(manifest)
    local esc_key = key:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local patched, count = text:gsub(
        '("' .. esc_key .. '"%s*:%s*)[^,%}\r\n]*',
        "%1" .. value,
        1
    )
    if count ~= 1 then
        io.stderr:write(
            "build-helper: set-mod-json-flag: '" .. key .. "' not found in "
            .. manifest .. "; skipping (flag left unchanged)\n"
        )
        return
    end
    write_text(manifest, patched)
end

local function patch_android_local_properties(args)
    local properties = args[2]
    local text = ""
    local f = io.open(properties, "rb")
    if f then
        text = f:read("*a")
        f:close()
    end
    text = remove_property_lines(text, "sdk.dir")
    text = set_gradle_property(text, "sdk.dir", local_properties_value(args[3]), properties)
    write_text(properties, text)
end

local function patch_android_properties(args)
    local properties = args[2]
    local text = read_text(properties)

    text = remove_property_lines(text, "app.name")
    text = remove_property_lines(text, "app.name_byte_array")

    local name = args[4]
    if is_ascii(name) then
        text = set_gradle_property(text, "app.name", name, properties)
    else
        local bytes = {}
        for i = 1, #name do
            bytes[#bytes + 1] = tostring(name:byte(i))
        end
        text = set_gradle_property(text, "app.name_byte_array", table.concat(bytes, ","), properties)
    end

    for _, kv in ipairs({
        { "app.application_id", args[3] },
        { "app.orientation", args[5] },
        { "app.version_code", args[6] },
        { "app.version_name", args[7] },
    }) do
        text = set_gradle_property(text, kv[1], kv[2], properties)
    end

    write_text(properties, text)
end

local GRADLE_ORIGINAL = [[    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
]]

local GRADLE_REPLACEMENT = [[    def signingKeystore = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE")
    def hasCustomSigning = signingKeystore != null && !signingKeystore.isEmpty()
    def signingStorePassword = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD")
    def signingKeyAlias = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS")
    def signingKeyPassword = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD")

    signingConfigs {
        if (hasCustomSigning) {
            release {
                storeFile file(signingKeystore)
                storePassword signingStorePassword
                keyAlias signingKeyAlias
                keyPassword signingKeyPassword
            }
        }
    }
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
            signingConfig = hasCustomSigning ? signingConfigs.release : signingConfigs.debug
        }
    }
]]

local function patch_android_gradle(args)
    local gradle = args[2]
    local text = read_text(gradle)
    text = replace_block(text, GRADLE_ORIGINAL, GRADLE_REPLACEMENT, gradle)
    write_text(gradle, text)
end

local ACTIVITY_ORIGINAL = [[        embed = getResources().getBoolean(R.bool.embed);

        if (!embed) {
]]

local ACTIVITY_REPLACEMENT = [[        embed = getResources().getBoolean(R.bool.embed);
        // Upstream skips handleIntent() for embed builds, so initialize the
        // asset-copy path explicitly before native LÖVE asks for the game.
        needToCopyGameInArchive = embed;

        if (!embed) {
]]

local function patch_android_game_activity(args)
    local source = args[2]
    local text = read_text(source)
    text = replace_block(text, ACTIVITY_ORIGINAL, ACTIVITY_REPLACEMENT, source)
    write_text(source, text)
end

local LOADING_ORIGINAL = [[function Loading:onKeyPressed(key)
    self.key_check = true
    self.skipped = true
    if self.loading_state == Loading.States.WAITING then
        self:beginLoad()
    end
end

return Loading
]]

local LOADING_REPLACEMENT = [[function Loading:onKeyPressed(key)
    self.key_check = true
    self.skipped = true
    if self.loading_state == Loading.States.WAITING then
        self:beginLoad()
    end
end

-- Android has no physical keyboard during the loading screen.
function love.touchpressed(...)
    local state = Kristal and Kristal.getState and Kristal.getState()
    if state == LoadingState and state.onKeyPressed then
        state:onKeyPressed("confirm")
    end
end

return Loading
]]

local function patch_android_loading_touch(args)
    local source = args[2]
    local text = read_text(source)
    text = replace_block(text, LOADING_ORIGINAL, LOADING_REPLACEMENT, source)
    write_text(source, text)
end

-- Validate manifests and write the library directories that a release package
-- must omit.  Deletion remains in the calling packager so this exact plan can
-- be consumed by both POSIX shell and native Windows tooling.
local function plan_release_libraries(args)
    local stage_mod_dir, plan_file = args[2], args[3]
    if not stage_mod_dir or not plan_file or args[4] then
        fail("plan-release-libraries: expected <stage_mod_dir> <plan_file>")
    end
    local ok, err = Manifest.write_release_library_plan(stage_mod_dir, plan_file)
    if not ok then fail(err) end
end

-- --- zip-dir (stored entries; LÖVE's physfs reads stored zips fine) --------

-- LÖVE 11 ships LuaJIT, which does not have Lua 5.3+ bitwise operators, so
-- use LuaJIT's bit library for the CRC-32 table and checksum.
local bit = require("bit")
local bxor = bit.bxor
local band = bit.band
local rshift = bit.rshift

local crc_table = {}
do
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if c % 2 == 1 then
                c = bxor(0xEDB88320, rshift(c, 1))
            else
                c = rshift(c, 1)
            end
        end
        crc_table[i] = c
    end
end

local function crc32(data)
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        crc = bxor(crc_table[band(bxor(crc, data:byte(i)), 0xFF)], rshift(crc, 8))
    end
    return bxor(crc, 0xFFFFFFFF)
end

local function u16(v)
    return string.char(v % 256, math.floor(v / 256) % 256)
end

local function u32(v)
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

-- Fixed DOS timestamp (2026-01-01 00:00:00) — deterministic archives.
local DOS_TIME, DOS_DATE = u16(0), u16((2026 - 1980) * 512 + 1 * 32 + 1)

-- Recursive file list: find on POSIX (works in Git Bash too), dir /s /b in
-- cmd — io.popen on Windows LuaJIT always goes through cmd.exe. /a-d restricts
-- dir to files (dir /s /b otherwise also emits directories, which io.open
-- cannot read). Keep the native Windows path here: Wine's cmd, and some older
-- cmd integrations, do not reliably enumerate a C:/... path.
local function file_list(source)
    local popen_cmd
    if love.system.getOS() == "Windows" then
        popen_cmd = 'dir /s /b /a-d "' .. source:gsub('"', '""') .. '"'
    else
        popen_cmd = "find " .. "'" .. source:gsub("'", "'\\''") .. "' -type f"
    end
    local p = io.popen(popen_cmd, "r")
    if not p then fail("cannot list " .. source) end
    local files = {}
    for line in p:lines() do
        files[#files + 1] = line
    end
    p:close()
    return files
end

local function zip_dir(args)
    local output, source, prefix = args[2], args[3], args[4] or ""
    local source_native = source
    local windows = love.system.getOS() == "Windows"
    if windows then
        source_native = source_native:gsub("/", "\\")
    end
    local source_path = source_native:gsub("\\", "/"):gsub("/+$", "")
    if source_path == "" then fail("zip-dir source is required") end
    prefix = prefix:gsub("^/+", ""):gsub("/+$", "")

    -- Prepare output.
    local out, err = io.open(output, "wb")
    if not out then fail("cannot write " .. output .. ": " .. tostring(err)) end

    local central = {}
    local offset = 0
    local count = 0

    local files = file_list(source_native)
    table.sort(files)
    for _, raw in ipairs(files) do
        local file = raw:gsub("\\", "/") -- dir /s /b uses backslashes
        local source_prefix = source_path .. "/"
        local compare_file = windows and file:lower() or file
        local compare_prefix = windows and source_prefix:lower() or source_prefix
        if compare_file:sub(1, #compare_prefix) ~= compare_prefix then
            fail("file list entry is outside source directory: " .. raw)
        end
        local relative = file:sub(#source_prefix + 1)
        if relative ~= "" then
            local skip = false
            if relative:find("__pycache__/", 1, true) then skip = true end
            if relative:match("%.pyc$") or relative:match("%.pyo$") then skip = true end
            if not skip then
                local f, err = io.open(file, "rb")
                if not f then fail("cannot read " .. file .. ": " .. tostring(err)) end
                local data = f:read("*a")
                f:close()

                local name = (prefix ~= "" and prefix .. "/" or "") .. relative
                local crc = crc32(data)
                local size = #data

                -- Local file header.
                out:write("PK\3\4", u16(20), u16(0x0800), u16(0), DOS_TIME, DOS_DATE,
                    u32(crc), u32(size), u32(size), u16(#name), u16(0))
                out:write(name, data)

                -- Central directory entry.
                central[#central + 1] = "PK\1\2" .. u16(20) .. u16(20) .. u16(0x0800) .. u16(0) ..
                    DOS_TIME .. DOS_DATE .. u32(crc) .. u32(size) .. u32(size) ..
                    u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0) ..
                    u32(0) .. u32(offset) .. name
                offset = offset + 30 + #name + size
                count = count + 1
            end
        end
    end

    local central_blob = table.concat(central)
    out:write(central_blob)
    out:write("PK\5\6", u16(0), u16(0), u16(count), u16(count),
        u32(#central_blob), u32(offset), u16(0))
    out:close()
end

-- --- dispatch ---------------------------------------------------------------

local function main()
    -- LÖVE 11 does not expose positional args via love.arg (its C-side
    -- parser drops them), so the shell hands them over in a file named by
    -- DELTARUNE_DDD_CH1_HELPER_ARGS (one argument per line).
    local args_file = os.getenv("DELTARUNE_DDD_CH1_HELPER_ARGS")
    if not args_file then
        fail("missing DELTARUNE_DDD_CH1_HELPER_ARGS (run via build-helper/lib.sh)")
    end
    local args = {}
    for line in io.lines(args_file) do
        args[#args + 1] = line
    end
    local command = args[1]
    if not command then
        fail("missing subcommand (patch-lua-config / patch-mod-manifest / patch-android-* / set-mod-json-flag / plan-release-libraries / zip-dir)")
    end
    if command == "patch-lua-config" then
        patch_lua_config(args)
    elseif command == "patch-mod-manifest" then
        patch_mod_manifest(args)
    elseif command == "patch-android-local-properties" then
        patch_android_local_properties(args)
    elseif command == "patch-android-properties" then
        patch_android_properties(args)
    elseif command == "patch-android-gradle" then
        patch_android_gradle(args)
    elseif command == "patch-android-game-activity" then
        patch_android_game_activity(args)
    elseif command == "patch-android-loading-touch" then
        patch_android_loading_touch(args)
    elseif command == "set-mod-json-flag" then
        set_mod_json_flag(args)
    elseif command == "plan-release-libraries" then
        plan_release_libraries(args)
    elseif command == "zip-dir" then
        zip_dir(args)
    else
        fail("unknown subcommand: " .. tostring(command))
    end
    -- LÖVE keeps running after main.lua returns; quit explicitly.
    love.event.quit()
end

main()
