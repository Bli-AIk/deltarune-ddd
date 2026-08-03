#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' \
        'Usage: ./start.sh [--name PROJECT_NAME] [--yes]' \
        '' \
        'Initialize this template with a project name and fetch all submodules.' \
        'When PROJECT_NAME is omitted, the Git root directory name is used.'
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)
project_root=${project_root:-$script_dir}

[ -f "$project_root/mod.json" ] || {
    printf 'Could not find mod.json in %s\n' "$project_root" >&2
    exit 1
}

old_id=$(sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' "$project_root/mod.json" | head -n 1)
old_display=$(sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' "$project_root/mod.json" | head -n 1)
[ -n "$old_id" ] && [ -n "$old_display" ] || {
    printf 'Could not read project id and name from %s/mod.json\n' "$project_root" >&2
    exit 1
}

default_name=$(basename -- "$project_root")
project_name=
assume_default=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --yes|-y)
            assume_default=1
            shift
            ;;
        --name|-n)
            [ "$#" -gt 1 ] || {
                printf '%s requires a value.\n' "$1" >&2
                exit 64
            }
            project_name=$2
            shift 2
            ;;
        --name=*)
            project_name=${1#--name=}
            shift
            ;;
        --*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
        *)
            [ -z "$project_name" ] || {
                printf 'Only one project name may be provided.\n' >&2
                exit 64
            }
            project_name=$1
            shift
            ;;
    esac
done

if [ -z "$project_name" ] && [ "$assume_default" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    printf 'Project name [%s]: ' "$default_name"
    IFS= read -r project_name || true
fi
project_name=${project_name:-$default_name}
project_name=$(printf '%s' "$project_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

[ -n "$project_name" ] || {
    printf '%s\n' 'Project name cannot be empty.' >&2
    exit 64
}
case "$project_name" in
    *$'\n'*|*$'\r'*)
        printf '%s\n' 'Project name cannot contain a newline.' >&2
        exit 64
        ;;
esac

lower() {
    LC_ALL=C tr '[:upper:]' '[:lower:]'
}

upper() {
    LC_ALL=C tr '[:lower:]' '[:upper:]'
}

slugify() {
    lower | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

project_id=$(printf '%s' "$project_name" | slugify)
[ -n "$project_id" ] || {
    printf '%s\n' 'Project name must contain at least one ASCII letter or number.' >&2
    exit 64
}

old_lower_spaced=$(printf '%s' "$old_display" | lower)
old_upper_spaced=$(printf '%s' "$old_display" | upper)
old_env_prefix=$(printf '%s' "$old_id" | sed 's/-/_/g' | upper)
old_upper_hyphen=$(printf '%s' "$old_id" | upper)
old_compact=$(printf '%s' "$old_id" | tr -d '_-')

# Some derived projects changed mod.json before this script was introduced.
# Keep the original template aliases so those projects can still be migrated.
legacy_id=$(printf 'thrash-%s' 'machine')
legacy_display=$(printf '%s %s' 'Thrash' 'Machine')
legacy_lower_spaced=$(printf '%s' "$legacy_display" | lower)
legacy_upper_spaced=$(printf '%s' "$legacy_display" | upper)
legacy_env_prefix=$(printf '%s' "$legacy_id" | sed 's/-/_/g' | upper)
legacy_upper_hyphen=$(printf '%s' "$legacy_id" | upper)
legacy_compact=$(printf '%s' "$legacy_id" | tr -d '_-')

new_lower_spaced=$(printf '%s' "$project_name" | lower)
new_upper_spaced=$(printf '%s' "$project_name" | upper)
new_env_prefix=$(printf '%s' "$project_id" | sed 's/-/_/g' | upper)
new_upper_hyphen=$(printf '%s' "$project_id" | upper)
new_compact=$(printf '%s' "$project_id" | tr -d '_-')
case "$new_env_prefix" in
    [0-9]*) new_env_prefix="PROJECT_$new_env_prefix" ;;
esac

template_id=$(git -C "$project_root" show HEAD:mod.json 2>/dev/null \
    | sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' \
    | head -n 1 || true)
template_display=$(git -C "$project_root" show HEAD:mod.json 2>/dev/null \
    | sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' \
    | head -n 1 || true)
template_id=${template_id:-$old_id}
template_display=${template_display:-$old_display}
template_lower_spaced=$(printf '%s' "$template_display" | lower)
template_upper_spaced=$(printf '%s' "$template_display" | upper)
template_env_prefix=$(printf '%s' "$template_id" | sed 's/-/_/g' | upper)
template_upper_hyphen=$(printf '%s' "$template_id" | upper)
template_compact=$(printf '%s' "$template_id" | tr -d '_-')

legacy_aliases_enabled=1
case "$old_id" in
    "$legacy_id"|"$legacy_id"-*|"$legacy_id"_*) legacy_aliases_enabled=0 ;;
esac
case "$template_id" in
    "$legacy_id"|"$legacy_id"-*|"$legacy_id"_*) legacy_aliases_enabled=0 ;;
esac
if [ "$legacy_aliases_enabled" -eq 0 ]; then
    # The full current/template ID handles this derived template name.
    # Disabling the short alias prevents it from being replaced twice.
    legacy_alias_sentinel=$(printf '__legacy_alias_disabled__')
    legacy_id=$legacy_alias_sentinel
    legacy_display=$legacy_alias_sentinel
    legacy_lower_spaced=$legacy_alias_sentinel
    legacy_upper_spaced=$legacy_alias_sentinel
    legacy_env_prefix=$legacy_alias_sentinel
    legacy_upper_hyphen=$legacy_alias_sentinel
    legacy_compact=$legacy_alias_sentinel
fi

command -v perl >/dev/null 2>&1 || {
    printf '%s\n' 'This script requires perl to replace template text.' >&2
    exit 1
}

changed_files=0
if [ "$old_id" != "$project_id" ] || [ "$old_display" != "$project_name" ] || \
    [ "$old_env_prefix" != "$new_env_prefix" ] || [ "$legacy_aliases_enabled" -eq 1 ]; then
    while IFS= read -r -d '' relative_file; do
        file="$project_root/$relative_file"
        OLD_ID="$old_id" NEW_ID="$project_id" \
        OLD_DISPLAY="$old_display" NEW_DISPLAY="$project_name" \
        OLD_LOWER_SPACED="$old_lower_spaced" NEW_LOWER_SPACED="$new_lower_spaced" \
        OLD_UPPER_SPACED="$old_upper_spaced" NEW_UPPER_SPACED="$new_upper_spaced" \
        OLD_ENV_PREFIX="$old_env_prefix" NEW_ENV_PREFIX="$new_env_prefix" \
        OLD_UPPER_HYPHEN="$old_upper_hyphen" NEW_UPPER_HYPHEN="$new_upper_hyphen" \
        OLD_COMPACT="$old_compact" NEW_COMPACT="$new_compact" \
        LEGACY_ID="$legacy_id" LEGACY_DISPLAY="$legacy_display" \
        LEGACY_LOWER_SPACED="$legacy_lower_spaced" NEW_LEGACY_LOWER_SPACED="$new_lower_spaced" \
        LEGACY_UPPER_SPACED="$legacy_upper_spaced" NEW_LEGACY_UPPER_SPACED="$new_upper_spaced" \
        LEGACY_ENV_PREFIX="$legacy_env_prefix" NEW_LEGACY_ENV_PREFIX="$new_env_prefix" \
        LEGACY_UPPER_HYPHEN="$legacy_upper_hyphen" NEW_LEGACY_UPPER_HYPHEN="$new_upper_hyphen" \
        LEGACY_COMPACT="$legacy_compact" NEW_LEGACY_COMPACT="$new_compact" \
        TEMPLATE_ID="$template_id" TEMPLATE_DISPLAY="$template_display" \
        TEMPLATE_LOWER_SPACED="$template_lower_spaced" \
        TEMPLATE_UPPER_SPACED="$template_upper_spaced" \
        TEMPLATE_ENV_PREFIX="$template_env_prefix" \
        TEMPLATE_UPPER_HYPHEN="$template_upper_hyphen" \
        TEMPLATE_COMPACT="$template_compact" \
            perl -0pi -e '
                s/\Q$ENV{LEGACY_ID}\E/$ENV{NEW_ID}/g;
                s/\Q$ENV{LEGACY_DISPLAY}\E/$ENV{NEW_DISPLAY}/g;
                s/\Q$ENV{LEGACY_LOWER_SPACED}\E/$ENV{NEW_LEGACY_LOWER_SPACED}/g;
                s/\Q$ENV{LEGACY_UPPER_SPACED}\E/$ENV{NEW_LEGACY_UPPER_SPACED}/g;
                s/\Q$ENV{LEGACY_ENV_PREFIX}\E/$ENV{NEW_LEGACY_ENV_PREFIX}/g;
                s/\Q$ENV{LEGACY_UPPER_HYPHEN}\E/$ENV{NEW_LEGACY_UPPER_HYPHEN}/g;
                s/\Q$ENV{LEGACY_COMPACT}\E/$ENV{NEW_LEGACY_COMPACT}/g;
                s/\Q$ENV{TEMPLATE_ID}\E/$ENV{NEW_ID}/g;
                s/\Q$ENV{TEMPLATE_DISPLAY}\E/$ENV{NEW_DISPLAY}/g;
                s/\Q$ENV{TEMPLATE_LOWER_SPACED}\E/$ENV{NEW_LOWER_SPACED}/g;
                s/\Q$ENV{TEMPLATE_UPPER_SPACED}\E/$ENV{NEW_UPPER_SPACED}/g;
                s/\Q$ENV{TEMPLATE_ENV_PREFIX}\E/$ENV{NEW_ENV_PREFIX}/g;
                s/\Q$ENV{TEMPLATE_UPPER_HYPHEN}\E/$ENV{NEW_UPPER_HYPHEN}/g;
                s/\Q$ENV{TEMPLATE_COMPACT}\E/$ENV{NEW_COMPACT}/g;
                s/\Q$ENV{OLD_ID}\E/$ENV{NEW_ID}/g;
                s/\Q$ENV{OLD_DISPLAY}\E/$ENV{NEW_DISPLAY}/g;
                s/\Q$ENV{OLD_LOWER_SPACED}\E/$ENV{NEW_LOWER_SPACED}/g;
                s/\Q$ENV{OLD_UPPER_SPACED}\E/$ENV{NEW_UPPER_SPACED}/g;
                s/\Q$ENV{OLD_ENV_PREFIX}\E/$ENV{NEW_ENV_PREFIX}/g;
                s/\Q$ENV{OLD_UPPER_HYPHEN}\E/$ENV{NEW_UPPER_HYPHEN}/g;
                s/\Q$ENV{OLD_COMPACT}\E/$ENV{NEW_COMPACT}/g;
            ' "$file"
        changed_files=$((changed_files + 1))
    done < <(
        git -C "$project_root" grep -Ilz -F \
            -e "$old_id" \
            -e "$old_display" \
            -e "$old_lower_spaced" \
            -e "$old_upper_spaced" \
            -e "$old_env_prefix" \
            -e "$old_upper_hyphen" \
            -e "$old_compact" \
            -e "$legacy_id" \
            -e "$legacy_display" \
            -e "$legacy_lower_spaced" \
            -e "$legacy_upper_spaced" \
            -e "$legacy_env_prefix" \
            -e "$legacy_upper_hyphen" \
            -e "$legacy_compact" \
            -e "$template_id" \
            -e "$template_display" \
            -e "$template_lower_spaced" \
            -e "$template_upper_spaced" \
            -e "$template_env_prefix" \
            -e "$template_upper_hyphen" \
            -e "$template_compact" \
            -- . || true
    )
fi

renamed_paths=0
tiled_project_path=
tiled_project_count=0
while IFS= read -r -d '' relative_file; do
    case "$relative_file" in
        */*) continue ;;
        *.tiled-project)
            tiled_project_path="$relative_file"
            tiled_project_count=$((tiled_project_count + 1))
            ;;
    esac
done < <(git -C "$project_root" ls-files -z -- '*.tiled-project')

while IFS= read -r -d '' relative_file; do
    old_file="$project_root/$relative_file"
    [ -f "$old_file" ] || continue

    new_relative_file=$(
        printf '%s' "$relative_file" | \
        OLD_ID="$old_id" NEW_PATH="$project_id" \
        OLD_LOWER_SPACED="$old_lower_spaced" \
        OLD_UPPER_SPACED="$old_upper_spaced" \
        OLD_ENV_PREFIX="$old_env_prefix" \
        OLD_UPPER_HYPHEN="$old_upper_hyphen" \
        OLD_COMPACT="$old_compact" \
        LEGACY_ID="$legacy_id" \
        LEGACY_LOWER_SPACED="$legacy_lower_spaced" \
        LEGACY_UPPER_SPACED="$legacy_upper_spaced" \
        LEGACY_ENV_PREFIX="$legacy_env_prefix" \
        LEGACY_UPPER_HYPHEN="$legacy_upper_hyphen" \
        LEGACY_COMPACT="$legacy_compact" \
        TEMPLATE_ID="$template_id" \
        TEMPLATE_LOWER_SPACED="$template_lower_spaced" \
        TEMPLATE_UPPER_SPACED="$template_upper_spaced" \
        TEMPLATE_ENV_PREFIX="$template_env_prefix" \
        TEMPLATE_UPPER_HYPHEN="$template_upper_hyphen" \
        TEMPLATE_COMPACT="$template_compact" \
            perl -0pe '
                s/\Q$ENV{LEGACY_ID}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{LEGACY_LOWER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{LEGACY_UPPER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{LEGACY_ENV_PREFIX}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{LEGACY_UPPER_HYPHEN}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{LEGACY_COMPACT}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_ID}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_LOWER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_UPPER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_ENV_PREFIX}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_UPPER_HYPHEN}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{OLD_COMPACT}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_ID}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_LOWER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_UPPER_SPACED}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_ENV_PREFIX}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_UPPER_HYPHEN}\E/$ENV{NEW_PATH}/g;
                s/\Q$ENV{TEMPLATE_COMPACT}\E/$ENV{NEW_PATH}/g;
            '
    )
    if [ "$new_relative_file" = "$relative_file" ] && \
        [ "$tiled_project_count" -eq 1 ] && [ "$relative_file" = "$tiled_project_path" ] && \
        [ "$relative_file" != "$project_id.tiled-project" ]; then
        new_relative_file="$project_id.tiled-project"
    fi
    [ "$new_relative_file" != "$relative_file" ] || continue

    new_file="$project_root/$new_relative_file"
    [ ! -e "$new_file" ] || {
        printf 'Cannot rename %s: target already exists at %s\n' \
            "$relative_file" "$new_relative_file" >&2
        exit 1
    }
    mkdir -p "$(dirname -- "$new_file")"
    mv -- "$old_file" "$new_file"
    renamed_paths=$((renamed_paths + 1))
done < <(git -C "$project_root" ls-files -z --)

printf 'Project name: %s\n' "$project_name"
printf 'Mod ID: %s\n' "$project_id"
printf 'Updated %s tracked text file(s).\n' "$changed_files"
printf 'Renamed %s tracked file path(s).\n' "$renamed_paths"
printf '%s\n' 'Updating submodules...'
git -C "$project_root" submodule update --init --recursive
printf '%s\n' 'Project initialization complete.'
