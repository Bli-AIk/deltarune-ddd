#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/deltarune-ddd-ch1-manifest.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

run_plan() {
    LUA_PATH="$root/build-helper/?.lua;;" luajit - "$1" "$2" <<'LUA'
local manifest = require("manifest")
local ok, err = manifest.write_release_library_plan(arg[1], arg[2], false)
if not ok then
    io.stderr:write(err .. "\n")
    os.exit(1)
end
LUA
}

expect_plan() {
    plan=$1
    shift
    printf '%s\n' "$@" > "$tmp/expected"
    diff -u "$tmp/expected" "$plan"
}

expect_failure() {
    if run_plan "$1" "$2" >/dev/null 2>&1; then
        printf '%s\n' 'manifest planner unexpectedly succeeded' >&2
        exit 1
    fi
}

write_mod() {
    stage=$1
    selection=$2
    printf '%s\n' \
        '{' \
        '  "name": "https://example.invalid//not-a-comment",' \
        '  // The field may appear anywhere and supports JSONC comments.' \
        "  \"optionalLibraries\": $selection," \
        '  "unrelated": [null, 1, {"text": "/* not a comment */"}],' \
        '}' > "$stage/mod.json"
}

write_library() {
    directory=$1
    id=$2
    dependencies=${3:-}
    mkdir -p "$directory"
    if [ -n "$dependencies" ]; then
        printf '%s\n' \
            '{' \
            "  \"dependencies\": [$dependencies]," \
            "  \"id\": \"$id\"," \
            '}' > "$directory/lib.json"
    else
        printf '%s\n' \
            '{' \
            "  \"id\": \"$id\"," \
            '}' > "$directory/lib.json"
    fi
}

stage="$tmp/stage with spaces"
libraries="$stage/libraries"
mkdir -p "$libraries"
write_library "$libraries/vendor-manager" magical-glass
write_library "$libraries/vendor-monsters" undertale_monsters_recreation '"magical-glass"'
mkdir -p "$libraries/unrelated"
printf '%s\n' \
    '{' \
    '  "optionalDependencies": ["magical-glass"],' \
    '  "id": "unrelated-library",' \
    '}' > "$libraries/unrelated/lib.json"
write_library "$libraries/dev-selector" kristal-object-selector-plus
write_library "$libraries/dev-terminal" terminal-cli
write_library "$libraries/dev-debug" kristal-debug-tools
# JSONC allows comments and a trailing comma in arrays. This library remains
# enabled, so a successful plan proves the parser consumed that array without
# accidentally including it in the release exclusions.
mkdir -p "$libraries/jsonc-array"
printf '%s\n' \
    '{' \
    '  "dependencies": [' \
    '    // Required at runtime.' \
    '    "magical-glass",' \
    '  ],' \
    '  "id": "jsonc-array",' \
    '}' > "$libraries/jsonc-array/lib.json"
plan="$tmp/plan"

# False UMR is planned by its ID even though its directory has a vendor name;
# comments, tail commas, and // inside a string must not confuse the parser.
write_mod "$stage" '{"undertale_monsters_recreation": false, "magical-glass": true}'
run_plan "$stage" "$plan"
expect_plan "$plan" dev-debug dev-selector dev-terminal vendor-monsters

# A disabled dependency carries all required dependents, but does not carry an
# unrelated library (nor optionalDependencies, which are intentionally ignored).
write_mod "$stage" '{"magical-glass": false, "undertale_monsters_recreation": true}'
run_plan "$stage" "$plan"
expect_plan "$plan" dev-debug dev-selector dev-terminal jsonc-array vendor-manager vendor-monsters

# A disabled submodule may be absent; an enabled one may not.
write_mod "$stage" '{"uninitialized-library": false}'
run_plan "$stage" "$plan"
expect_plan "$plan" dev-debug dev-selector dev-terminal
write_mod "$stage" '{"uninitialized-library": true}'
expect_failure "$stage" "$plan"

# A damaged staging tree must not silently become an empty library set.
missing_libraries_stage="$tmp/missing-libraries"
mkdir -p "$missing_libraries_stage"
write_mod "$missing_libraries_stage" '{}'
expect_failure "$missing_libraries_stage" "$plan"

file_libraries_stage="$tmp/file-libraries"
mkdir -p "$file_libraries_stage"
write_mod "$file_libraries_stage" '{}'
: > "$file_libraries_stage/libraries"
expect_failure "$file_libraries_stage" "$plan"

# Manifest type errors and retained required dependencies fail explicitly.
write_mod "$stage" '[]'
expect_failure "$stage" "$plan"
write_library "$libraries/missing-dependent" missing-dependent '"not-in-stage"'
write_mod "$stage" '{}'
expect_failure "$stage" "$plan"
rm -rf "$libraries/missing-dependent"

# IDs, rather than directory names, are the unique release-policy key.
write_library "$libraries/duplicate-one" duplicate-library
write_library "$libraries/duplicate-two" duplicate-library
expect_failure "$stage" "$plan"

printf '%s\n' 'build helper manifest smoke: PASS'
