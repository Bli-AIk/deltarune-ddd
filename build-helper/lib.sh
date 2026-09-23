# Shared wiring for the build scripts: locate LÖVE (the user already has it
# to run the mod) and run build-helper/main.lua — no Python needed.
#
# Source this after setting DELTARUNE_DDD_CH1_MOD_DIR.

# --- severity-labeled output ---------------------------------------------------
# Info messages keep the caller's prefix (log); warnings and errors are labeled
# so a build that merely skips an optional step (no `zip`, no icon tool, ...)
# does not read like a crash.
warn() {
    printf '[警告] %s\n' "$*" >&2
}

fail() {
    printf '[错误] %s\n' "$*" >&2
    exit 1
}

resolve_love() {
    if [ -n "${LOVE:-}" ] && command -v "$LOVE" >/dev/null 2>&1; then
        command -v "$LOVE"
        return
    fi
    if command -v love >/dev/null 2>&1; then
        command -v love
        return
    fi
    for dir in "$PROGRAMFILES/LOVE" "$LOCALAPPDATA/Programs/LOVE"; do
        if [ -f "$dir/love.exe" ]; then
            printf '%s\n' "$dir/love.exe"
            return
        fi
    done
    return 1
}

DELTARUNE_DDD_CH1_LOVE="${DELTARUNE_DDD_CH1_LOVE:-}"
if [ -z "$DELTARUNE_DDD_CH1_LOVE" ]; then
    DELTARUNE_DDD_CH1_LOVE="$(resolve_love)" || {
        fail 'Missing required command: love (LÖVE). Install it from https://love2d.org'
    }
fi

# --- shared tools dir (hosted outside the mod tree) -----------------------------
# Auto-downloaded tools (JDK, Android SDK, rcedit, GUI, PortableGit) live under
# <kristal-root>/.tools so every mod based on this template shares one cache AND
# the mod tree stays free of the JDK's symlinks, which crash Kristal's mod
# loader on Windows (filesystemutils.lua: getInfo returns nil for the broken
# junctions; the engine has no nil guard and must not be patched).
# Resolution is local-first: nearest engine by walking up from the mod root
# (the "mod inside engine/mods/" layout) wins, so a mod living inside its own
# engine fork is never hijacked by a KRISTAL_ROOT inherited from the shell
# profile; explicit KRISTAL_ROOT / DELTARUNE_DDD_CH1_KRISTAL_DIR are only a
# fallback for mods outside an engine tree; finally <mod>/.tools (a Linux
# template without a shared engine; .tools is untouched by `clean-build`, and
# Linux PHYSFS resolves the symlinks fine). Set DELTARUNE_DDD_CH1_TOOLS_DIR to
# pin the location explicitly.
detect_kristal_root() {
    local candidate dir parent
    # Local-first, mirroring bin/kristal-run: the nearest engine by walking up
    # from the mod root wins, so a mod inside its own engine fork is never
    # hijacked by a KRISTAL_ROOT inherited from the shell profile.
    dir="$DELTARUNE_DDD_CH1_MOD_DIR"
    while :; do
        if [ -f "$dir/main.lua" ] && [ -f "$dir/src/kristal.lua" ]; then
            printf '%s\n' "$dir"; return 0
        fi
        parent=$(dirname "$dir")
        [ "$parent" = "$dir" ] && break
        dir=$parent
    done
    # Explicit env vars are only a fallback for mods outside an engine tree.
    # `:-` keeps this safe when sourced by a `set -u` script (build_*.sh all do).
    for candidate in "${KRISTAL_ROOT:-}" "${DELTARUNE_DDD_CH1_KRISTAL_DIR:-}"; do
        [ -n "$candidate" ] || continue
        # DELTARUNE_DDD_CH1_KRISTAL_DIR defaults to the mod-root clone
        # .build/Kristal — inside the mod, not a shared host. Skip it.
        [ "$candidate" = "$DELTARUNE_DDD_CH1_MOD_DIR/.build/Kristal" ] && continue
        [ -f "$candidate/main.lua" ] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}
DELTARUNE_DDD_CH1_TOOLS_DIR="${DELTARUNE_DDD_CH1_TOOLS_DIR:-}"
if [ -z "$DELTARUNE_DDD_CH1_TOOLS_DIR" ]; then
    _kr="$(detect_kristal_root || true)"
    DELTARUNE_DDD_CH1_TOOLS_DIR="${_kr:+$_kr/.tools}"
    : "${DELTARUNE_DDD_CH1_TOOLS_DIR:=$DELTARUNE_DDD_CH1_MOD_DIR/.tools}"
fi

# Native Windows binaries (love.exe) cannot open msys-style paths such as
# /c/Users/... Convert absolute paths to Windows form (C:/...) when running
# under Git Bash / msys; no-op on Linux and for relative or non-path args.
win_path() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            case "$1" in
                /*) command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s\n' "$1" ;;
                *) printf '%s\n' "$1" ;;
            esac
            ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# Open a directory in the platform's file manager (Windows → explorer, Linux →
# xdg-open, macOS → open). Best-effort and non-fatal: skipped in non-interactive
# shells (CI never pops a window) and when DELTARUNE_DDD_CH1_NO_OPEN_DIR=1 (the
# Android launchers set it for the nested build_standalone.sh subprocess so it
# does not open an internal staging dir). Only warns when the opener is missing.
open_output_dir() {
    [ "${DELTARUNE_DDD_CH1_NO_OPEN_DIR:-0}" = "1" ] && return 0
    [ -t 1 ] || [ -t 2 ] || return 0
    local dir="$1"
    [ -d "$dir" ] || { warn "输出目录不存在，无法打开: $dir"; return 0; }
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # explorer.exe needs backslashes: a forward-slash path (what
            # win_path/cygpath -m produces) makes the shell fail to resolve it
            # and fall back to a default folder (Documents). win_path keeps its
            # forward slashes for the other callers, so convert again here.
            local win_dir="$dir"
            case "$dir" in
                /*) command -v cygpath >/dev/null 2>&1 && win_dir="$(cygpath -w "$dir")" ;;
            esac
            if command -v explorer >/dev/null 2>&1; then
                explorer "$win_dir" >/dev/null 2>&1 &
            elif command -v cmd >/dev/null 2>&1; then
                cmd //c start "" "$win_dir" >/dev/null 2>&1 &
            else
                warn "未找到资源管理器，无法打开输出目录: $dir"
            fi
            ;;
        Darwin*)
            if command -v open >/dev/null 2>&1; then
                open "$dir" >/dev/null 2>&1 &
            else
                warn "未找到 open，无法打开输出目录: $dir"
            fi
            ;;
        *)
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$dir" >/dev/null 2>&1 &
            else
                warn "未找到 xdg-open，无法打开输出目录: $dir"
            fi
            ;;
    esac
}

run_helper() {
    # LÖVE 11 drops positional args after the game path, so pass them in a
    # temp file (one argument per line). love.exe is a native binary, so msys
    # paths (/c/...) written here must be converted to Windows form first.
    local args_file arg status
    args_file="$(mktemp)" || fail '无法创建临时文件（mktemp 失败）'
    : > "$args_file"
    for arg in "$@"; do
        win_path "$arg" >> "$args_file"
    done
    DELTARUNE_DDD_CH1_HELPER_ARGS="$(win_path "$args_file")" \
        "$DELTARUNE_DDD_CH1_LOVE" "$DELTARUNE_DDD_CH1_MOD_DIR/build-helper"
    status=$?
    rm -f "$args_file"
    return $status
}

# Ask the Lua helper which staged libraries a release excludes (development
# tools, disabled optional libraries, and required dependents), then remove
# only the immediate directories it named. Manifest parsing and dependency
# handling live in one place; this shell code deliberately owns just the
# irreversible filesystem operation.
prune_release_optional_libraries() {
    local stage_mod="$1" plan_file entry unsafe_entry=""
    [ -d "$stage_mod" ] || fail "暂存项目目录不存在: $stage_mod"
    plan_file="$(mktemp)" || fail '无法创建库裁剪计划临时文件（mktemp 失败）'

    if ! run_helper plan-release-libraries "$stage_mod" "$plan_file"; then
        rm -f "$plan_file"
        return 1
    fi

    while IFS= read -r entry || [ -n "$entry" ]; do
        case "$entry" in
            ''|.|..|*/*|*\\*|*$'\r'*|*$'\n'*)
                unsafe_entry="$entry"
                break
                ;;
        esac
        rm -rf -- "$stage_mod/libraries/$entry"
    done < "$plan_file"
    rm -f "$plan_file"
    [ -z "$unsafe_entry" ] || fail "库裁剪计划包含不安全目录名: $unsafe_entry"
}

zip_dir() {
    local output="$1" source="$2" prefix="${3:-}" total _count=0

    # The zip invocations below run in a subshell after cd'ing into the
    # source directory, so resolve a relative output path against the caller's
    # working directory first (CI passes e.g. DELTARUNE_DDD_CH1_OUTPUT_DIR=dist-win).
    case "$output" in
        /*) ;;
        *) output="$(pwd -P)/$output" ;;
    esac

    mkdir -p "$(dirname "$output")"
    rm -f "$output"

    if command -v zip >/dev/null 2>&1; then
        if [ -t 1 ]; then
            total="$(find "$source" -mindepth 1 2>/dev/null | wc -l | tr -d '[:space:]')"
            total="${total:-0}"
            printf '\r[build] zip %s: 0/%s' "$(basename "$output")" "$total" >&2
            if [ -n "$prefix" ]; then
                (cd "$(dirname "$source")" && zip -9 -r "$output" "$(basename "$source")") |
                    while IFS= read -r _; do
                        printf '\r[build] zip %s: %s/%s' "$(basename "$output")" "$((_count += 1))" "$total" >&2
                    done
            else
                (cd "$source" && zip -9 -r "$output" .) |
                    while IFS= read -r _; do
                        printf '\r[build] zip %s: %s/%s' "$(basename "$output")" "$((_count += 1))" "$total" >&2
                    done
            fi
            printf '\r[build] zip %s: done (%s files)\n' "$(basename "$output")" "$total" >&2
        else
            if [ -n "$prefix" ]; then
                (cd "$(dirname "$source")" && zip -9 -q -r "$output" "$(basename "$source")")
            else
                (cd "$source" && zip -9 -q -r "$output" .)
            fi
        fi
    else
        # No system `zip` (Git Bash has none) — this is a normal fallback, not
        # an error. Warn once per run so repeated archives stay quiet.
        if [ "${DELTARUNE_DDD_CH1_ZIP_FALLBACK_WARNED:-0}" != "1" ]; then
            warn "未找到系统 zip，改用 LÖVE 内置压缩助手（正常，构建继续）"
            DELTARUNE_DDD_CH1_ZIP_FALLBACK_WARNED=1
        fi
        run_helper zip-dir "$output" "$source" "$prefix"
        printf '[build] zip %s: done (LÖVE helper)\n' "$(basename "$output")" >&2
    fi
}

# --- portable JDK (used by the Android build scripts) -------------------------
# A pristine machine usually has no JDK. When the caller did not pin one via
# DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME/JAVA_HOME and no usable `java` is on PATH,
# ensure_java downloads a portable Temurin JDK 17 into $DELTARUNE_DDD_CH1_TOOLS_DIR/jdk17
# (the shared tools dir outside the mod tree) and exports JAVA_HOME/PATH. Disable
# the download with DELTARUNE_DDD_CH1_FETCH_JDK=0.
# These functions use the warn/fail helpers defined at the top of this file, so
# the sourcing scripts do not need to define their own before sourcing.
DELTARUNE_DDD_CH1_JDK_DIR="${DELTARUNE_DDD_CH1_JDK_DIR:-$DELTARUNE_DDD_CH1_TOOLS_DIR/jdk17}"
DELTARUNE_DDD_CH1_FETCH_JDK="${DELTARUNE_DDD_CH1_FETCH_JDK:-1}"

java_major() {
    # Quoted and unquoted variants: real JDKs print `version "17.0.11"` (with
    # quotes); a few minimal builds omit them. Two POSIX BRE subs instead of an
    # optional-quote token (not portable across BSD/GNU sed).
    "$1" -version 2>&1 \
        | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p; s/.*version \([0-9][0-9]*\).*/\1/p' \
        | head -n 1
}

# Resolve a JDK and export JAVA_HOME/PATH for the rest of the script.
#   ensure_java            — use any working Java (explicit home or PATH), else
#                            download JDK 17.
#   ensure_java <major>    — additionally require that major version (an
#                            explicit home or PATH java of a different major is
#                            an error / triggers the download), else download.
# Exits 1 with a clear message when nothing usable is available.
ensure_java() {
    local exact="${1:-}" version="${1:-17}" java_home major
    java_home="${DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME:-${JAVA_HOME:-}}"
    if [ -n "$java_home" ]; then
        [ -x "$java_home/bin/java" ] || {
            fail "Configured Java home has no Java executable: $java_home"
        }
        if [ -n "$exact" ]; then
            major="$(java_major "$java_home/bin/java")"
            [ "$major" = "$exact" ] || {
                fail "Java $exact required, found ${major:-unknown} at $java_home (set DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME to a JDK $exact)"
            }
        fi
        export JAVA_HOME="$java_home"
        export PATH="$JAVA_HOME/bin:$PATH"
        return 0
    fi
    if command -v java >/dev/null 2>&1; then
        if [ -n "$exact" ]; then
            major="$(java_major "$(command -v java)")"
            if [ "$major" = "$exact" ]; then
                use_path_java
                return 0
            fi
        else
            use_path_java
            return 0
        fi
    fi
    install_portable_jdk "$version"
    export JAVA_HOME="$DELTARUNE_DDD_CH1_JDK_DIR"
    export PATH="$JAVA_HOME/bin:$PATH"
}

use_path_java() {
    JAVA_HOME="$(CDPATH= cd -- "$(dirname -- "$(command -v java)")/.." && pwd -P)"
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
}

# Download + unpack a Temurin JDK of the given major version into
# DELTARUNE_DDD_CH1_JDK_DIR (archive cached in .build/cache). Reuses an existing
# installation instead of re-downloading ~190 MB every build.
install_portable_jdk() {
    local version="$1" dest="$DELTARUNE_DDD_CH1_JDK_DIR"
    # Windows JDKs ship bin/java.exe, POSIX ones bin/java — accept either.
    if [ -x "$dest/bin/java" ] || [ -x "$dest/bin/java.exe" ]; then
        printf 'JDK %s 已存在: %s\n' "$version" "$dest" >&2
        return 0
    fi
    [ "$DELTARUNE_DDD_CH1_FETCH_JDK" = "1" ] || {
        fail "No JDK $version found and DELTARUNE_DDD_CH1_FETCH_JDK=0; install JDK $version or set DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME"
    }
    local os arch cache url cd_out archive extract top
    case "$(uname -s)" in
        Linux*) os=linux ;;
        Darwin*) os=mac ;;
        MINGW*|MSYS*|CYGWIN*) os=windows ;;
        *) fail "Unsupported OS for portable JDK: $(uname -s)" ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) fail "Unsupported architecture for portable JDK: $(uname -m)" ;;
    esac
    command -v curl >/dev/null 2>&1 || fail 'curl is required to download the portable JDK'
    command -v unzip >/dev/null 2>&1 || fail 'unzip is required to unpack the portable JDK'

    cache="$DELTARUNE_DDD_CH1_MOD_DIR/.build/cache"
    mkdir -p "$cache"
    url="https://api.adoptium.net/v3/binary/latest/${version}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"
    printf '下载便携 JDK %s（Temurin %s/%s，约 190 MB）…\n' "$version" "$os" "$arch" >&2
    cd_out="$(mktemp)"
    cd_err="$(mktemp)"
    if ! (cd "$cache" && curl --fail --location --remote-name --remote-header-name \
            --write-out '%{filename_effective}' "$url") > "$cd_out" 2> "$cd_err"; then
        err_tail="$(tr -d '\r' < "$cd_err" | grep . | tail -n 2)"
        rm -f "$cd_out" "$cd_err"
        fail "下载 JDK $version 失败: $url${err_tail:+（curl: $err_tail）}"
    fi
    rm -f "$cd_err"
    archive="$cache/$(cat "$cd_out")"
    rm -f "$cd_out"
    [ -f "$archive" ] || fail "JDK 下载未产生文件（$url）"

    extract="$dest.extract"
    rm -rf "$extract" "$dest"
    mkdir -p "$extract"
    case "$archive" in
        *.zip)
            unzip -q "$archive" -d "$extract" || {
                rm -rf "$extract" "$dest"
                fail "解压 JDK 失败: $archive"
            }
            ;;
        *.tar.gz|*.tgz)
            command -v tar >/dev/null 2>&1 || {
                rm -rf "$extract" "$dest"
                fail 'tar is required to unpack the portable JDK'
            }
            tar -xzf "$archive" -C "$extract" || {
                rm -rf "$extract" "$dest"
                fail "解压 JDK 失败: $archive"
            }
            ;;
        *)
            rm -rf "$extract" "$dest"
            fail "无法识别的 JDK 包: $archive"
            ;;
    esac
    top="$(find "$extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -n "$top" ]; then
        mv "$top" "$dest"
    else
        mv "$extract" "$dest"
    fi
    rm -rf "$extract"
    if [ ! -x "$dest/bin/java" ] && [ ! -x "$dest/bin/java.exe" ]; then
        rm -rf "$dest"
        fail "JDK $version 缺少 bin/java: $dest"
    fi
    printf 'JDK %s 已就绪: %s\n' "$version" "$dest" >&2
}

# git is required to fetch the Kristal engine. The GUI sidecar auto-downloads
# PortableGit into the shared tools dir (.tools/portablegit next to the Kristal
# root) on Windows, but a plain bash invocation has no such fallback (installing
# system git needs root and is distro-specific, so we only point the user at the
# right command). Self-contained: no log/fail.
need_git() {
    command -v git >/dev/null 2>&1 && return 0
    cat >&2 <<'EOF'
[错误] Missing required command: git

Git is needed to fetch the Kristal engine. Install it, then re-run:

  - Windows:  winget install Git.Git
              (or run the GUI — it auto-downloads PortableGit into the shared .tools/portablegit)
  - Linux:    sudo apt install git        # Debian / Ubuntu
              sudo dnf install git        # Fedora
              sudo pacman -S git          # Arch
  - macOS:    xcode-select --install

EOF
    exit 1
}
