-- Release-library manifest reader. It only owns the policy needed by the
-- packagers: optional selections, library IDs, and required dependencies.

local Manifest = {}

-- Release policy is expressed as library IDs, never submodule directory names.
local DEVELOPMENT_LIBRARY_IDS = {
    ["kristal-object-selector-plus"] = true,
    ["terminal-cli"] = true,
    ["kristal-debug-tools"] = true,
}

local ARRAY_VALUES = setmetatable({}, { __mode = "k" })
local JSON_NULL = {}

local function line_and_column(text, position)
    local line, last_newline = 1, 0
    for newline in text:sub(1, math.max(position - 1, 0)):gmatch("()\n") do
        line = line + 1
        last_newline = newline
    end
    return line, position - last_newline
end

local function parse_error(reader, message)
    local line, column = line_and_column(reader.text, reader.position)
    error(string.format("%s:%d:%d: %s", reader.source, line, column, message), 0)
end

local function skip_space_and_comments(reader)
    while reader.position <= reader.length do
        local byte = reader.text:byte(reader.position)
        if byte == 0x20 or byte == 0x09 or byte == 0x0A or byte == 0x0D then
            reader.position = reader.position + 1
        elseif reader.text:sub(reader.position, reader.position + 1) == "//" then
            local newline = reader.text:find("[\r\n]", reader.position + 2)
            reader.position = newline and newline or reader.length + 1
        elseif reader.text:sub(reader.position, reader.position + 1) == "/*" then
            local close = reader.text:find("*/", reader.position + 2, true)
            if not close then parse_error(reader, "unterminated block comment") end
            reader.position = close + 2
        else
            return
        end
    end
end

local function utf8_from_codepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end
    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40
    )
end

local function read_hex4(reader)
    local digits = reader.text:sub(reader.position, reader.position + 3)
    if #digits ~= 4 or not digits:match("^%x%x%x%x$") then
        parse_error(reader, "expected four hexadecimal digits in \\u escape")
    end
    reader.position = reader.position + 4
    return tonumber(digits, 16)
end

local function parse_string(reader)
    if reader.text:sub(reader.position, reader.position) ~= '"' then
        parse_error(reader, "expected string")
    end
    reader.position = reader.position + 1
    local out = {}
    while reader.position <= reader.length do
        local byte = reader.text:byte(reader.position)
        if byte == 0x22 then
            reader.position = reader.position + 1
            return table.concat(out)
        elseif byte < 0x20 then
            parse_error(reader, "control character in string")
        elseif byte ~= 0x5C then
            out[#out + 1] = string.char(byte)
            reader.position = reader.position + 1
        else
            reader.position = reader.position + 1
            local escape = reader.text:sub(reader.position, reader.position)
            if escape == '"' or escape == "\\" or escape == "/" then
                out[#out + 1] = escape
                reader.position = reader.position + 1
            elseif escape == "b" then
                out[#out + 1], reader.position = "\b", reader.position + 1
            elseif escape == "f" then
                out[#out + 1], reader.position = "\f", reader.position + 1
            elseif escape == "n" then
                out[#out + 1], reader.position = "\n", reader.position + 1
            elseif escape == "r" then
                out[#out + 1], reader.position = "\r", reader.position + 1
            elseif escape == "t" then
                out[#out + 1], reader.position = "\t", reader.position + 1
            elseif escape == "u" then
                reader.position = reader.position + 1
                local codepoint = read_hex4(reader)
                if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                    if reader.text:sub(reader.position, reader.position + 1) ~= "\\u" then
                        parse_error(reader, "high surrogate must be followed by a low surrogate")
                    end
                    reader.position = reader.position + 2
                    local low = read_hex4(reader)
                    if low < 0xDC00 or low > 0xDFFF then
                        parse_error(reader, "high surrogate must be followed by a low surrogate")
                    end
                    codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + low - 0xDC00
                elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                    parse_error(reader, "unexpected low surrogate")
                end
                out[#out + 1] = utf8_from_codepoint(codepoint)
            else
                parse_error(reader, "invalid string escape")
            end
        end
    end
    parse_error(reader, "unterminated string")
end

local function skip_number(reader)
    local text = reader.text
    if text:sub(reader.position, reader.position) == "-" then
        reader.position = reader.position + 1
    end
    local first = text:sub(reader.position, reader.position)
    if first == "0" then
        reader.position = reader.position + 1
        if text:sub(reader.position, reader.position):match("%d") then
            parse_error(reader, "leading zero in number")
        end
    elseif first:match("[1-9]") then
        repeat
            reader.position = reader.position + 1
        until not text:sub(reader.position, reader.position):match("%d")
    else
        parse_error(reader, "invalid number")
    end
    if text:sub(reader.position, reader.position) == "." then
        reader.position = reader.position + 1
        if not text:sub(reader.position, reader.position):match("%d") then
            parse_error(reader, "expected digit after decimal point")
        end
        repeat
            reader.position = reader.position + 1
        until not text:sub(reader.position, reader.position):match("%d")
    end
    local exponent = text:sub(reader.position, reader.position)
    if exponent == "e" or exponent == "E" then
        reader.position = reader.position + 1
        local sign = text:sub(reader.position, reader.position)
        if sign == "+" or sign == "-" then reader.position = reader.position + 1 end
        if not text:sub(reader.position, reader.position):match("%d") then
            parse_error(reader, "expected digit in exponent")
        end
        repeat
            reader.position = reader.position + 1
        until not text:sub(reader.position, reader.position):match("%d")
    end
end

local parse_value

local function parse_object(reader)
    if reader.text:sub(reader.position, reader.position) ~= "{" then
        parse_error(reader, "expected object")
    end
    reader.position = reader.position + 1
    skip_space_and_comments(reader)
    local object = {}
    if reader.text:sub(reader.position, reader.position) == "}" then
        reader.position = reader.position + 1
        return object
    end

    local seen = {}
    while true do
        if reader.text:sub(reader.position, reader.position) ~= '"' then
            parse_error(reader, "expected string key in object")
        end
        local key = parse_string(reader)
        if seen[key] then parse_error(reader, "duplicate object key " .. string.format("%q", key)) end
        seen[key] = true
        skip_space_and_comments(reader)
        if reader.text:sub(reader.position, reader.position) ~= ":" then
            parse_error(reader, "expected ':' after object key")
        end
        reader.position = reader.position + 1
        object[key] = parse_value(reader)
        skip_space_and_comments(reader)
        local delimiter = reader.text:sub(reader.position, reader.position)
        if delimiter == "}" then
            reader.position = reader.position + 1
            return object
        elseif delimiter ~= "," then
            parse_error(reader, "expected ',' or '}' in object")
        end
        reader.position = reader.position + 1
        skip_space_and_comments(reader)
        if reader.text:sub(reader.position, reader.position) == "}" then
            reader.position = reader.position + 1
            return object
        end
    end
end

local function parse_array(reader)
    if reader.text:sub(reader.position, reader.position) ~= "[" then
        parse_error(reader, "expected array")
    end
    reader.position = reader.position + 1
    skip_space_and_comments(reader)
    local array = {}
    ARRAY_VALUES[array] = true
    if reader.text:sub(reader.position, reader.position) == "]" then
        reader.position = reader.position + 1
        return array
    end

    while true do
        array[#array + 1] = parse_value(reader)
        skip_space_and_comments(reader)
        local delimiter = reader.text:sub(reader.position, reader.position)
        if delimiter == "]" then
            reader.position = reader.position + 1
            return array
        elseif delimiter ~= "," then
            parse_error(reader, "expected ',' or ']' in array")
        end
        reader.position = reader.position + 1
        skip_space_and_comments(reader)
        if reader.text:sub(reader.position, reader.position) == "]" then
            reader.position = reader.position + 1
            return array
        end
    end
end

parse_value = function(reader)
    skip_space_and_comments(reader)
    local next_char = reader.text:sub(reader.position, reader.position)
    if next_char == '"' then
        return parse_string(reader)
    elseif next_char == "{" then
        return parse_object(reader)
    elseif next_char == "[" then
        return parse_array(reader)
    elseif next_char == "t" and reader.text:sub(reader.position, reader.position + 3) == "true" then
        reader.position = reader.position + 4
        return true
    elseif next_char == "f" and reader.text:sub(reader.position, reader.position + 4) == "false" then
        reader.position = reader.position + 5
        return false
    elseif next_char == "n" and reader.text:sub(reader.position, reader.position + 3) == "null" then
        reader.position = reader.position + 4
        return JSON_NULL
    elseif next_char == "-" or next_char:match("%d") then
        skip_number(reader)
        return 0
    end
    parse_error(reader, "expected JSON value")
end

local function read_manifest(path)
    local file, read_err = io.open(path, "rb")
    if not file then return nil, "cannot read " .. path .. ": " .. tostring(read_err) end
    local text = file:read("*a")
    file:close()

    local ok, manifest_or_err = pcall(function()
        local reader = { text = text, source = path, position = 1, length = #text }
        if text:sub(1, 3) == "\239\187\191" then reader.position = 4 end
        local manifest = parse_value(reader)
        skip_space_and_comments(reader)
        if reader.position <= reader.length then parse_error(reader, "unexpected trailing content") end
        if type(manifest) ~= "table" or ARRAY_VALUES[manifest] then
            parse_error(reader, "root must be an object")
        end
        return manifest
    end)
    if not ok then return nil, tostring(manifest_or_err) end
    return manifest_or_err
end

local function optional_library_selection(path)
    local manifest, err = read_manifest(path)
    if not manifest then return nil, err end
    local selection = manifest.optionalLibraries
    if selection == nil then return {} end
    if type(selection) ~= "table" or ARRAY_VALUES[selection] then
        return nil, path .. ": optionalLibraries must be an object"
    end
    for id, enabled in pairs(selection) do
        if type(id) ~= "string" or id == "" or type(enabled) ~= "boolean" then
            return nil, path .. ": optionalLibraries must map non-empty IDs to booleans"
        end
    end
    return selection
end

local function library_manifest(path)
    local manifest, err = read_manifest(path)
    if not manifest then return nil, err end
    if type(manifest.id) ~= "string" or manifest.id == "" then
        return nil, path .. ": id must be a non-empty string"
    end
    local dependencies = manifest.dependencies
    if dependencies == nil then
        dependencies = {}
    elseif type(dependencies) ~= "table" or not ARRAY_VALUES[dependencies] then
        return nil, path .. ": dependencies must be an array"
    end
    for _, dependency in ipairs(dependencies) do
        if type(dependency) ~= "string" or dependency == "" then
            return nil, path .. ": dependencies entries must be non-empty strings"
        end
    end
    return { id = manifest.id, dependencies = dependencies }
end

local function is_windows(default)
    if default ~= nil then return default end
    return love and love.system and love.system.getOS and love.system.getOS() == "Windows"
end

local function quote_posix(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function quote_windows(value)
    return '"' .. value:gsub('"', '""') .. '"'
end

local function join_path(base, child)
    if base:sub(-1) == "/" or base:sub(-1) == "\\" then return base .. child end
    return base .. "/" .. child
end

local function basename(path)
    return path:gsub("[\\/]$", ""):match("([^\\/]+)$")
end

local function is_safe_directory_name(name)
    return name ~= nil
        and name ~= ""
        and name ~= "."
        and name ~= ".."
        and not name:find("\\", 1, true)
        and not name:find("/", 1, true)
        and not name:find("\r", 1, true)
        and not name:find("\n", 1, true)
        and not name:find("\0", 1, true)
end

local function library_directories(stage_dir, windows)
    local libraries_dir = join_path(stage_dir, "libraries")
    local status_prefix = ":tm-manifest-status:"
    local status_ok = status_prefix .. "ok"
    local status_missing = status_prefix .. "missing"
    local status_error = status_prefix .. "error"
    local command
    if windows then
        -- LuaJIT's io.popen():close() does not reliably expose cmd's exit
        -- status. The final marker makes success observable.
        local native_libraries_dir = libraries_dir:gsub("/", "\\")
        command = "pushd " .. quote_windows(native_libraries_dir) .. " >nul 2>nul"
            .. " && (dir /b /ad 2>nul & popd & echo " .. status_ok .. ")"
            .. " || echo " .. status_missing
    else
        -- A NUL delimiter preserves unusual but valid POSIX directory names.
        local quoted_dir = quote_posix(libraries_dir)
        local emit_ok = "printf '%s\\000' " .. quote_posix(status_ok)
        local emit_error = "printf '%s\\000' " .. quote_posix(status_error)
        local emit_missing = "printf '%s\\000' " .. quote_posix(status_missing)
        command = "if [ -d " .. quoted_dir .. " ]; then if find " .. quoted_dir
            .. " -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null; then "
            .. emit_ok .. "; else " .. emit_error .. "; fi; else " .. emit_missing .. "; fi"
    end
    local process = io.popen(command, "r")
    if not process then return nil, "cannot list " .. libraries_dir end

    local entries = {}
    if windows then
        for line in process:lines() do entries[#entries + 1] = line:gsub("\r$", "") end
    else
        for line in (process:read("*a") or ""):gmatch("(.-)%z") do entries[#entries + 1] = line end
    end
    process:close()

    local status = entries[#entries]
    if status ~= status_ok then
        if status == status_missing then
            return nil, "library directory is missing or is not a directory: " .. libraries_dir
        elseif status == status_error then
            return nil, "cannot enumerate library directory: " .. libraries_dir
        end
        return nil, "cannot list " .. libraries_dir
    end
    entries[#entries] = nil

    local directories = {}
    for _, line in ipairs(entries) do
        local name = windows and line or basename(line)
        if not is_safe_directory_name(name) then
            return nil, "unsafe library directory name in " .. libraries_dir
        end
        directories[#directories + 1] = {
            name = name,
            path = windows and join_path(libraries_dir, name) or line,
        }
    end
    table.sort(directories, function(a, b) return a.name < b.name end)
    return directories
end

-- Write one immediate libraries/ child directory name per line for release
-- exclusions: dev tools, disabled optional libraries, and required dependents.
function Manifest.write_release_library_plan(stage_dir, plan_path, windows)
    if type(stage_dir) ~= "string" or stage_dir == "" then
        return nil, "plan-release-libraries: stage directory is required"
    end
    if type(plan_path) ~= "string" or plan_path == "" then
        return nil, "plan-release-libraries: plan path is required"
    end

    local selection, selection_err = optional_library_selection(join_path(stage_dir, "mod.json"))
    if not selection then return nil, selection_err end
    local directories, directory_err = library_directories(stage_dir, is_windows(windows))
    if not directories then return nil, directory_err end

    local libraries = {}
    for _, directory in ipairs(directories) do
        local manifest_path = join_path(directory.path, "lib.json")
        local file = io.open(manifest_path, "rb")
        if file then
            file:close()
            local library, library_err = library_manifest(manifest_path)
            if not library then return nil, library_err end
            if libraries[library.id] then
                return nil, string.format(
                    "duplicate library ID %q in %s and %s",
                    library.id, libraries[library.id].manifest_path, manifest_path
                )
            end
            library.directory_name = directory.name
            library.manifest_path = manifest_path
            libraries[library.id] = library
        end
    end

    local disabled = {}
    for id in pairs(DEVELOPMENT_LIBRARY_IDS) do
        if libraries[id] then disabled[id] = true end
    end
    for id, enabled in pairs(selection) do
        if enabled then
            if not libraries[id] then return nil, "enabled optional library is missing: " .. id end
        else
            -- False is valid even when the corresponding submodule is absent.
            disabled[id] = true
        end
    end

    local changed = true
    while changed do
        changed = false
        for id, library in pairs(libraries) do
            if not disabled[id] then
                for _, dependency in ipairs(library.dependencies) do
                    if disabled[dependency] then
                        disabled[id] = true
                        changed = true
                        break
                    end
                end
            end
        end
    end

    for id, library in pairs(libraries) do
        if not disabled[id] then
            for _, dependency in ipairs(library.dependencies) do
                if not libraries[dependency] then
                    return nil, string.format(
                        "retained library %q requires missing dependency %q", id, dependency
                    )
                end
            end
        end
    end

    local entries = {}
    for id, library in pairs(libraries) do
        if disabled[id] then entries[#entries + 1] = library.directory_name end
    end
    table.sort(entries)

    local output, output_err = io.open(plan_path, "wb")
    if not output then return nil, "cannot write " .. plan_path .. ": " .. tostring(output_err) end
    for _, entry in ipairs(entries) do output:write(entry, "\n") end
    output:close()
    return true
end

return Manifest
