#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DELTARUNE_DDD_CH1_MOD_DIR="${DELTARUNE_DDD_CH1_MOD_DIR:-$SCRIPT_DIR}"
DELTARUNE_DDD_CH1_MOD_DIR="$(CDPATH= cd -- "$DELTARUNE_DDD_CH1_MOD_DIR" && pwd -P)"
DELTARUNE_DDD_CH1_BUILD_ROOT="${DELTARUNE_DDD_CH1_BUILD_ROOT:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/standalone}"
DELTARUNE_DDD_CH1_OUTPUT_DIR="${DELTARUNE_DDD_CH1_OUTPUT_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/dist}"
DELTARUNE_DDD_CH1_CACHE_DIR="${DELTARUNE_DDD_CH1_CACHE_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/cache}"

DELTARUNE_DDD_CH1_KRISTAL_REPO="${DELTARUNE_DDD_CH1_KRISTAL_REPO:-https://github.com/KristalTeam/Kristal.git}"
DELTARUNE_DDD_CH1_KRISTAL_REF="${DELTARUNE_DDD_CH1_KRISTAL_REF:-v0.10.0}"
DELTARUNE_DDD_CH1_KRISTAL_EXPECTED_VERSION="${DELTARUNE_DDD_CH1_KRISTAL_EXPECTED_VERSION:-0.10.0}"
DELTARUNE_DDD_CH1_KRISTAL_DIR="${DELTARUNE_DDD_CH1_KRISTAL_DIR:-${KRISTAL_ROOT:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/Kristal}}"

DELTARUNE_DDD_CH1_MOD_ID="${DELTARUNE_DDD_CH1_MOD_ID:-deltarune-ddd-ch1}"
DELTARUNE_DDD_CH1_PROJECT_TITLE="${DELTARUNE_DDD_CH1_PROJECT_TITLE:-deltarune distant, divergent dream}"
DELTARUNE_DDD_CH1_OUTPUT_BASENAME="${DELTARUNE_DDD_CH1_OUTPUT_BASENAME:-deltarune-ddd-ch1}"
DELTARUNE_DDD_CH1_EXE_BASENAME="${DELTARUNE_DDD_CH1_EXE_BASENAME:-DELTARUNE-DDD-CH1}"
DELTARUNE_DDD_CH1_LOVE_VERSION="${DELTARUNE_DDD_CH1_LOVE_VERSION:-11.5}"
DELTARUNE_DDD_CH1_LOVE_ARCH="${DELTARUNE_DDD_CH1_LOVE_ARCH:-win64}"
DELTARUNE_DDD_CH1_LOVE_WINDOWS_ZIP_URL="${DELTARUNE_DDD_CH1_LOVE_WINDOWS_ZIP_URL:-https://github.com/love2d/love/releases/download/${DELTARUNE_DDD_CH1_LOVE_VERSION}/love-${DELTARUNE_DDD_CH1_LOVE_VERSION}-${DELTARUNE_DDD_CH1_LOVE_ARCH}.zip}"
DELTARUNE_DDD_CH1_BUILD_VARIANTS="${DELTARUNE_DDD_CH1_BUILD_VARIANTS:-release debug}"
DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE="${DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE:-1}"
DELTARUNE_DDD_CH1_UPDATE_REPOS="${DELTARUNE_DDD_CH1_UPDATE_REPOS:-0}"

log() {
    printf '[build] %s\n' "$*" >&2
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$1" >&2
        exit 1
    }
}

ensure_kristal() {
    if [ -d "$DELTARUNE_DDD_CH1_KRISTAL_DIR/.git" ]; then
        if [ "$DELTARUNE_DDD_CH1_UPDATE_REPOS" = "1" ]; then
            git -C "$DELTARUNE_DDD_CH1_KRISTAL_DIR" fetch --tags origin
        fi
    elif [ -e "$DELTARUNE_DDD_CH1_KRISTAL_DIR" ]; then
        printf 'Kristal path exists but is not a Git checkout: %s\n' "$DELTARUNE_DDD_CH1_KRISTAL_DIR" >&2
        exit 1
    else
        mkdir -p "$(dirname "$DELTARUNE_DDD_CH1_KRISTAL_DIR")"
        git clone --filter=blob:none "$DELTARUNE_DDD_CH1_KRISTAL_REPO" "$DELTARUNE_DDD_CH1_KRISTAL_DIR"
    fi

    if ! git -C "$DELTARUNE_DDD_CH1_KRISTAL_DIR" rev-parse --verify --quiet "${DELTARUNE_DDD_CH1_KRISTAL_REF}^{commit}" >/dev/null; then
        git -C "$DELTARUNE_DDD_CH1_KRISTAL_DIR" fetch --depth 1 origin "refs/tags/${DELTARUNE_DDD_CH1_KRISTAL_REF}:refs/tags/${DELTARUNE_DDD_CH1_KRISTAL_REF}"
    fi

    version="$(git -C "$DELTARUNE_DDD_CH1_KRISTAL_DIR" show "${DELTARUNE_DDD_CH1_KRISTAL_REF}:VERSION" | tr -d '\r\n')"
    if [ "$version" != "$DELTARUNE_DDD_CH1_KRISTAL_EXPECTED_VERSION" ]; then
        printf 'Kristal %s reports VERSION=%s, expected %s\n' "$DELTARUNE_DDD_CH1_KRISTAL_REF" "$version" "$DELTARUNE_DDD_CH1_KRISTAL_EXPECTED_VERSION" >&2
        exit 1
    fi
}

export_kristal() {
    stage_dir="$1"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    git -C "$DELTARUNE_DDD_CH1_KRISTAL_DIR" archive --format=tar "$DELTARUNE_DDD_CH1_KRISTAL_REF" | tar -x -C "$stage_dir"
    rm -rf "$stage_dir/.github" "$stage_dir/mods" "$stage_dir/build" "$stage_dir/output"
}

copy_mod() {
    stage_mod="$1"
    variant="$2"
    mkdir -p "$stage_mod"
    rsync -a \
        --exclude='/.git/' \
        --exclude='.git' \
        --exclude='/.github/' \
        --exclude='/.build/' \
        --exclude='/dist/' \
        --exclude='/.emacs/' \
        --exclude='/.helix/' \
        --exclude='/.vscode/' \
        --exclude='/.worktrees/' \
        --exclude='/tests/' \
        --exclude='/docs/' \
        --exclude='/Makefile' \
        --exclude='/justfile' \
        --exclude='/build_standalone.sh' \
        --exclude='/build_standalone.py' \
        --exclude='/build_android.sh' \
        --exclude='__pycache__/' \
        --exclude='*.pyc' \
        --exclude='*.pyo' \
        --exclude='/release-please-config.json' \
        --exclude='/.release-please-manifest.json' \
        --exclude='/.gitmodules' \
        --exclude='/.gitignore' \
        --exclude='*.tiled-project' \
        --exclude='*.tiled-session' \
        "$DELTARUNE_DDD_CH1_MOD_DIR/" "$stage_mod/"

    if [ "$variant" = "release" ]; then
        rm -rf "$stage_mod/libraries/object-editor"
        rm -rf "$stage_mod/libraries/terminal-cli"
        rm -rf "$stage_mod/libraries/kristal-debug-tools"
    fi
}

zip_dir() {
    output="$1"
    source="$2"
    prefix="${3:-}"
    mkdir -p "$(dirname "$output")"
    rm -f "$output"
    if command -v zip >/dev/null 2>&1; then
        if [ -n "$prefix" ]; then
            (cd "$(dirname "$source")" && zip -9 -q -r "$output" "$(basename "$source")")
        else
            (cd "$source" && zip -9 -q -r "$output" .)
        fi
    else
        python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" zip-dir "$output" "$source" "$prefix"
    fi
}

prepare_stage() {
    variant="$1"
    case "$variant" in
        release)
            release_mode=true
            mod_dev=false
            object_editor=false
            ;;
        debug)
            release_mode=false
            mod_dev=true
            object_editor=true
            ;;
        *)
            printf 'Unknown build variant: %s\n' "$variant" >&2
            exit 1
            ;;
    esac

    stage_dir="$DELTARUNE_DDD_CH1_BUILD_ROOT/$variant/source"
    export_kristal "$stage_dir"
    stage_mod="$stage_dir/mods/$DELTARUNE_DDD_CH1_MOD_ID"
    copy_mod "$stage_mod" "$variant"
    if [ "$variant" = "release" ]; then
        identity="$DELTARUNE_DDD_CH1_MOD_ID"
        title="$DELTARUNE_DDD_CH1_PROJECT_TITLE"
    else
        identity="${DELTARUNE_DDD_CH1_MOD_ID}_debug"
        title="${DELTARUNE_DDD_CH1_PROJECT_TITLE} Debug"
    fi
    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-lua-config \
        "$stage_dir" "$DELTARUNE_DDD_CH1_MOD_ID" "$release_mode" \
        "$identity" "$title"
    if [ "${DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO:-0}" = "1" ]; then
        python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-android-loading-touch \
            "$stage_dir/src/engine/loadstate.lua"
    fi
    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-mod-manifest \
        "$stage_mod/mod.json" "$mod_dev" "$object_editor"
    printf '%s\n' "$stage_dir"
}

ensure_love_windows() {
    [ "$DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE" = "1" ] || return 0
    mkdir -p "$DELTARUNE_DDD_CH1_CACHE_DIR"
    love_zip="$DELTARUNE_DDD_CH1_CACHE_DIR/love-${DELTARUNE_DDD_CH1_LOVE_VERSION}-${DELTARUNE_DDD_CH1_LOVE_ARCH}.zip"
    love_dir="$DELTARUNE_DDD_CH1_CACHE_DIR/love-${DELTARUNE_DDD_CH1_LOVE_VERSION}-${DELTARUNE_DDD_CH1_LOVE_ARCH}"
    if [ ! -f "$love_zip" ]; then
        curl --fail --location --output "$love_zip" "$DELTARUNE_DDD_CH1_LOVE_WINDOWS_ZIP_URL"
    fi
    if [ ! -d "$love_dir" ]; then
        extract_dir="$DELTARUNE_DDD_CH1_CACHE_DIR/love-${DELTARUNE_DDD_CH1_LOVE_VERSION}-${DELTARUNE_DDD_CH1_LOVE_ARCH}.extract"
        rm -rf "$extract_dir"
        mkdir -p "$extract_dir"
        unzip -q "$love_zip" -d "$extract_dir"
        extracted="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        [ -n "$extracted" ] || {
            printf 'Could not locate the extracted LÖVE directory\n' >&2
            exit 1
        }
        mv "$extracted" "$love_dir"
        rm -rf "$extract_dir"
    fi
    test -f "$love_dir/love.exe"
}

build_variant() {
    variant="$1"
    stage_dir="$(prepare_stage "$variant")"
    love_file="$DELTARUNE_DDD_CH1_OUTPUT_DIR/${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-${variant}.love"
    zip_dir "$love_file" "$stage_dir"

    if [ "$DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE" = "1" ]; then
        love_dir="$DELTARUNE_DDD_CH1_CACHE_DIR/love-${DELTARUNE_DDD_CH1_LOVE_VERSION}-${DELTARUNE_DDD_CH1_LOVE_ARCH}"
        package_name="${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-${variant}-${DELTARUNE_DDD_CH1_LOVE_ARCH}"
        package_dir="$DELTARUNE_DDD_CH1_OUTPUT_DIR/$package_name"
        exe_name="${DELTARUNE_DDD_CH1_EXE_BASENAME}-${variant}.exe"
        rm -rf "$package_dir"
        mkdir -p "$package_dir"
        cat "$love_dir/love.exe" "$love_file" > "$package_dir/$exe_name"
        cp "$love_dir"/*.dll "$package_dir/"
        test ! -f "$love_dir/license.txt" || cp "$love_dir/license.txt" "$package_dir/"
        zip_dir "$DELTARUNE_DDD_CH1_OUTPUT_DIR/${package_name}.zip" "$package_dir" "$package_name"
    fi
}

need_cmd git
need_cmd python3
need_cmd rsync
need_cmd tar
need_cmd unzip
need_cmd curl
need_cmd zip
ensure_kristal
mkdir -p "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
ensure_love_windows
for variant in $DELTARUNE_DDD_CH1_BUILD_VARIANTS; do
    build_variant "$variant"
done
