#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Scripts live in tools/; the mod root is one level up.
DELTARUNE_DDD_CH1_MOD_DIR="${DELTARUNE_DDD_CH1_MOD_DIR:-$(CDPATH= cd -- "$(dirname -- "$SCRIPT_DIR")" && pwd -P)}"
DELTARUNE_DDD_CH1_MOD_DIR="$(CDPATH= cd -- "$DELTARUNE_DDD_CH1_MOD_DIR" && pwd -P)"
DELTARUNE_DDD_CH1_OUTPUT_DIR="${DELTARUNE_DDD_CH1_OUTPUT_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/dist}"
DELTARUNE_DDD_CH1_ANDROID_WORK_DIR="${DELTARUNE_DDD_CH1_ANDROID_WORK_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/android}"
DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR="${DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/cache/love-android-11.5}"

DELTARUNE_DDD_CH1_ANDROID_REPO="${DELTARUNE_DDD_CH1_ANDROID_REPO:-https://github.com/love2d/love-android.git}"
DELTARUNE_DDD_CH1_ANDROID_REF="${DELTARUNE_DDD_CH1_ANDROID_REF:-11.5}"
DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID="${DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID:-org.deltarunedddch1.template}"
DELTARUNE_DDD_CH1_ANDROID_NAME="${DELTARUNE_DDD_CH1_ANDROID_NAME:-deltarune-ddd-ch1}"
DELTARUNE_DDD_CH1_ANDROID_ORIENTATION="${DELTARUNE_DDD_CH1_ANDROID_ORIENTATION:-landscape}"
DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE="${DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE:-1}"
DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME="${DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME:-}"
DELTARUNE_DDD_CH1_ANDROID_ICON="${DELTARUNE_DDD_CH1_ANDROID_ICON:-}"
# Directory mode takes precedence over the single-file DELTARUNE_DDD_CH1_ANDROID_ICON:
# icons named <density>.png (ldpi/mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi); a missing
# density falls back to the nearest available one.
DELTARUNE_DDD_CH1_ANDROID_ICON_DIR="${DELTARUNE_DDD_CH1_ANDROID_ICON_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/assets/icon/android}"
DELTARUNE_DDD_CH1_ANDROID_NDK_DIR="${DELTARUNE_DDD_CH1_ANDROID_NDK_DIR:-}"
DELTARUNE_DDD_CH1_OUTPUT_BASENAME="${DELTARUNE_DDD_CH1_OUTPUT_BASENAME:-deltarune-ddd-ch1}"
DELTARUNE_DDD_CH1_FETCH_SDK="${DELTARUNE_DDD_CH1_FETCH_SDK:-1}"

log() {
    printf '[android-build] %s\n' "$*" >&2
}

fail() {
    printf '[错误] %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

# shellcheck source=build-helper/lib.sh
source "$DELTARUNE_DDD_CH1_MOD_DIR/build-helper/lib.sh"

# Defaulted here rather than in the top variable block: the shared tools dir
# (DELTARUNE_DDD_CH1_TOOLS_DIR) is only resolved when lib.sh is sourced above.
DELTARUNE_DDD_CH1_ANDROID_SDK_DIR="${DELTARUNE_DDD_CH1_ANDROID_SDK_DIR:-$DELTARUNE_DDD_CH1_TOOLS_DIR/android-sdk}"

read_mod_version() {
    version="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$DELTARUNE_DDD_CH1_MOD_DIR/mod.json" | head -n 1)"
    [ -n "$version" ] || fail "Could not find mod.json version"
    printf '%s\n' "${version#v}"
}

# --- Android SDK auto-install -------------------------------------------------
# A fresh machine usually has no Android SDK. When ANDROID_SDK_ROOT/ANDROID_HOME
# is unset (or set but missing a required component), download cmdline-tools and
# let sdkmanager install the required platform / build-tools / NDK into
# DELTARUNE_DDD_CH1_ANDROID_SDK_DIR ($DELTARUNE_DDD_CH1_TOOLS_DIR/android-sdk by
# default — the shared tools dir outside the mod tree, same location the Windows
# launcher build_android.ps1 uses). Disable with DELTARUNE_DDD_CH1_FETCH_SDK=0.

android_sdk_complete() {
    local sdk="$1"
    [ -d "$sdk/platforms/android-34" ] || return 1
    [ -d "$sdk/build-tools/34.0.0" ] || return 1
    [ -d "$sdk/ndk/25.2.9519653" ] || return 1
    [ -f "$sdk/ndk/25.2.9519653/source.properties" ] || return 1
}

# sdkmanager is a native .bat (Windows) / sh script (POSIX): the SDK root must
# reach it in host path form. win_path leaves C:/... unchanged and converts the
# /c/... MSYS form Git Bash would otherwise hand to cmd; package ids carry no
# slashes, so nothing else needs converting.
run_sdkmanager() {
    local sdkmanager="$1"
    shift
    MSYS2_ARG_CONV_EXCL='*' "$sdkmanager" --sdk_root="$(win_path "$ANDROID_SDK_ROOT")" "$@"
}

install_android_sdk() {
    local sdk="$DELTARUNE_DDD_CH1_ANDROID_SDK_DIR"
    local os url archive extract top
    local sdkmanager_cmd="$sdk/cmdline-tools/latest/bin/sdkmanager"
    local sdkmanager

    # sdkmanager is a sh script (POSIX) or sdkmanager.bat (Windows). Test with
    # -f, not -x: MSYS does not mark extracted .bat files executable, so -x
    # would report a perfectly good sdkmanager.bat as missing.
    if [ -f "$sdkmanager_cmd" ] || [ -f "$sdkmanager_cmd.bat" ]; then
        log "Android SDK cmdline-tools 已存在: $sdk"
    else
        case "$(uname -s)" in
            Linux*) os=linux ;;
            # The download URL spells the Windows channel "win" (three letters),
            # not "windows" — e.g. commandlinetools-win-11076708_latest.zip.
            MINGW*|MSYS*|CYGWIN*) os=win ;;
            *) fail "Unsupported OS for Android SDK download: $(uname -s)" ;;
        esac
        need_cmd curl
        need_cmd unzip

        archive="$DELTARUNE_DDD_CH1_MOD_DIR/.build/cache/commandlinetools-${os}-11076708_latest.zip"
        if [ ! -f "$archive" ]; then
            mkdir -p "$(dirname "$archive")"
            url="https://dl.google.com/android/repository/commandlinetools-${os}-11076708_latest.zip"
            log "下载 Android SDK cmdline-tools（约 130 MB）…"
            curl --fail --location --output "$archive" "$url" || fail \
                "下载 Android cmdline-tools 失败: $url"
        fi

        extract="$sdk/.cmdline-tools.extract"
        rm -rf "$extract"
        mkdir -p "$extract"
        unzip -q "$archive" -d "$extract" || {
            rm -rf "$extract"
            fail "解压 Android cmdline-tools 失败: $archive"
        }
        # The zip unpacks a single cmdline-tools/ directory; move it to the
        # latest/ slot sdkmanager expects.
        rm -rf "$sdk/cmdline-tools"
        mkdir -p "$sdk/cmdline-tools/latest"
        if [ -d "$extract/cmdline-tools" ]; then
            cp -R "$extract/cmdline-tools/." "$sdk/cmdline-tools/latest/"
        else
            cp -R "$extract/." "$sdk/cmdline-tools/latest/"
        fi
        rm -rf "$extract"
        [ -f "$sdkmanager_cmd" ] || [ -f "$sdkmanager_cmd.bat" ] || fail \
            "Android cmdline-tools 解压后未找到 sdkmanager"
    fi

    if [ -f "$sdkmanager_cmd" ]; then
        sdkmanager="$sdkmanager_cmd"
    else
        sdkmanager="$sdkmanager_cmd.bat"
    fi

    log "接受 Android SDK 许可协议…"
    # A bounded stream of 'y' lines: unlike `yes`, it writes into the pipe
    # buffer and exits before sdkmanager closes stdin, so pipefail never sees a
    # spurious SIGPIPE (141) on a successful run.
    printf 'y\n%.0s' {1..100} | run_sdkmanager "$sdkmanager" --licenses || fail "sdkmanager --licenses 失败"
    log "安装 Android SDK 组件（platforms;android-34 / build-tools;34.0.0 / ndk;25.2.9519653，首次约 1.5 GB）…"
    run_sdkmanager "$sdkmanager" "platforms;android-34" "build-tools;34.0.0" "ndk;25.2.9519653" || fail "sdkmanager 安装组件失败"
}

ensure_android_sdk() {
    local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

    if [ -n "$sdk" ] && android_sdk_complete "$sdk"; then
        export ANDROID_SDK_ROOT="$sdk"
        return 0
    fi
    if [ -n "$sdk" ]; then
        warn "Android SDK 位于 $sdk 但缺少必需组件，改用自动安装的 SDK"
    fi
    [ "$DELTARUNE_DDD_CH1_FETCH_SDK" = "1" ] || fail \
        "缺少完整的 Android SDK 且 DELTARUNE_DDD_CH1_FETCH_SDK=0；请设置 ANDROID_SDK_ROOT 指向含 API 34 和 NDK 25.2.9519653 的 SDK"

    # Point sdkmanager at the target dir before installing into it.
    export ANDROID_SDK_ROOT="$DELTARUNE_DDD_CH1_ANDROID_SDK_DIR"
    install_android_sdk
}

check_inputs() {
    local ndk_dir

    need_git
    need_cmd find
    # LÖVE Android 11.5 requires JDK 17. ensure_java honors an explicit
    # DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME/JAVA_HOME (wrong version is an error) or
    # a matching `java` on PATH, and auto-downloads a portable JDK 17 into
    # $DELTARUNE_DDD_CH1_TOOLS_DIR/jdk17 (shared tools dir) when the box has none.
    ensure_java 17

    # Resolve the SDK (auto-installing a missing one — see ensure_android_sdk),
    # then strictly verify every piece the build needs is actually there.
    ensure_android_sdk
    [ -d "$ANDROID_SDK_ROOT/platforms/android-34" ] || fail \
        "Missing Android SDK platform android-34 under $ANDROID_SDK_ROOT"
    [ -d "$ANDROID_SDK_ROOT/build-tools/34.0.0" ] || fail \
        "Missing Android Build Tools 34.0.0 under $ANDROID_SDK_ROOT"

    ndk_dir="${DELTARUNE_DDD_CH1_ANDROID_NDK_DIR:-$ANDROID_SDK_ROOT/ndk/25.2.9519653}"
    [ -d "$ndk_dir" ] || fail \
        "Missing Android NDK 25.2.9519653 under $ndk_dir"
    [ -f "$ndk_dir/source.properties" ] || fail \
        "Android NDK source.properties is missing under $ndk_dir"
    grep -Eq '^Pkg\.Revision[[:space:]]*=[[:space:]]*25\.2\.9519653[[:space:]]*$' \
        "$ndk_dir/source.properties" || fail \
        "Android NDK under $ndk_dir is not version 25.2.9519653"
    DELTARUNE_DDD_CH1_ANDROID_NDK_DIR="$ndk_dir"

    if [ -n "${DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE:-}" ]; then
        [ -f "$DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE" ] || fail \
            "Android signing keystore does not exist: $DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE"
        [ -n "${DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD:-}" ] || fail \
            "DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD is required with a custom Android keystore"
        [ -n "${DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS:-}" ] || fail \
            "DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS is required with a custom Android keystore"
        [ -n "${DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD:-}" ] || fail \
            "DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD is required with a custom Android keystore"

        DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE="$(CDPATH= cd -- "$(dirname -- "$DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE")" && pwd -P)/$(basename -- "$DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE")"
        export DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE
    fi

    printf '%s' "$DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID" \
        | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' || fail \
        "Invalid Android application id: $DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID"
    [ -n "$DELTARUNE_DDD_CH1_ANDROID_NAME" ] || fail "Android application name cannot be empty"
    case "$DELTARUNE_DDD_CH1_ANDROID_ORIENTATION" in
        landscape|portrait|sensorLandscape|sensorPortrait) ;;
        *) fail "Unsupported Android orientation: $DELTARUNE_DDD_CH1_ANDROID_ORIENTATION" ;;
    esac
    printf '%s' "$DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE" | grep -Eq '^[1-9][0-9]*$' || fail \
        "Android version code must be a positive integer"

    if [ -z "$DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME" ]; then
        DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME="$(read_mod_version)"
    fi
    [ -n "$DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME" ] || fail "Android version name cannot be empty"
}

ensure_android_source() {
    if [ -d "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR/.git" ]; then
        if ! git -C "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" rev-parse --verify --quiet \
            "${DELTARUNE_DDD_CH1_ANDROID_REF}^{commit}" >/dev/null; then
            git -C "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" fetch --depth 1 origin \
                "refs/tags/${DELTARUNE_DDD_CH1_ANDROID_REF}:refs/tags/${DELTARUNE_DDD_CH1_ANDROID_REF}"
        fi
    elif [ -e "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" ]; then
        fail "Android cache path exists but is not a Git checkout: $DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR"
    else
        mkdir -p "$(dirname "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR")"
        log "Cloning LÖVE Android ${DELTARUNE_DDD_CH1_ANDROID_REF}"
        git clone --recurse-submodules --depth 1 --branch "$DELTARUNE_DDD_CH1_ANDROID_REF" \
            "$DELTARUNE_DDD_CH1_ANDROID_REPO" "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR"
    fi

    git -C "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" checkout --detach "$DELTARUNE_DDD_CH1_ANDROID_REF" >/dev/null
    git -C "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" submodule update --init --recursive
}

android_density_dpi() {
    case "$1" in
        ldpi) echo 120 ;; mdpi) echo 160 ;; hdpi) echo 240 ;;
        xhdpi) echo 320 ;; xxhdpi) echo 480 ;; xxxhdpi) echo 640 ;;
    esac
}

# Print the path of the density icon nearest to $1 (smallest dpi difference),
# or nothing when the icon dir has no usable png at all.
pick_android_icon() {
    local target="$1" d best="" best_d=999999 diff
    for d in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
        [ -f "$DELTARUNE_DDD_CH1_ANDROID_ICON_DIR/$d.png" ] || continue
        diff=$(( $(android_density_dpi "$target") - $(android_density_dpi "$d") ))
        diff=${diff#-}
        if [ "$diff" -lt "$best_d" ]; then best="$d"; best_d="$diff"; fi
    done
    [ -n "$best" ] && printf '%s\n' "$DELTARUNE_DDD_CH1_ANDROID_ICON_DIR/$best.png"
}

# Copy launcher icons into res/drawable-<density>/love.png. Directory mode wins
# when the dir holds any <density>.png (only density-named files count — a
# stray png must not hijack the mode); otherwise fall back to the legacy
# single-file mode; if neither is configured, love-android's default stays.
stage_android_icons() {
    local stage="$1" density source
    local density_dir_has_icon=0

    for density in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
        [ -f "$DELTARUNE_DDD_CH1_ANDROID_ICON_DIR/$density.png" ] && density_dir_has_icon=1
    done

    if [ -n "$DELTARUNE_DDD_CH1_ANDROID_ICON_DIR" ] && [ "$density_dir_has_icon" = "1" ]; then
        for density in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
            # pick_android_icon returns non-zero when no density matches; keep
            # the build going (set -e) and let the nearest-density fallback
            # fill any gap from the files that do exist.
            source="$(pick_android_icon "$density" || true)"
            [ -n "$source" ] || continue
            mkdir -p "$stage/app/src/main/res/drawable-$density"
            cp "$source" "$stage/app/src/main/res/drawable-$density/love.png"
        done
        return 0
    fi

    if [ -n "$DELTARUNE_DDD_CH1_ANDROID_ICON" ]; then
        [ -f "$DELTARUNE_DDD_CH1_ANDROID_ICON" ] || fail \
            "Android icon does not exist: $DELTARUNE_DDD_CH1_ANDROID_ICON"
        for density in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
            mkdir -p "$stage/app/src/main/res/drawable-$density"
            cp "$DELTARUNE_DDD_CH1_ANDROID_ICON" \
                "$stage/app/src/main/res/drawable-$density/love.png"
        done
    fi
}

stage_android_source() {
    local stage_dir="$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/project"

    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    # tar instead of rsync (rsync is not available in Git Bash on Windows).
    tar -cf - --exclude='*.git' \
        -C "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR" . | tar -xf - -C "$stage_dir"
    mkdir -p "$stage_dir/app/src/embed/assets"
    cp "$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/love/${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-release.love" \
        "$stage_dir/app/src/embed/assets/game.love"

    stage_android_icons "$stage_dir"

    run_helper patch-android-properties \
        "$stage_dir/gradle.properties" \
        "$DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID" \
        "$DELTARUNE_DDD_CH1_ANDROID_NAME" \
        "$DELTARUNE_DDD_CH1_ANDROID_ORIENTATION" \
        "$DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE" \
        "$DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME"
    run_helper patch-android-gradle \
        "$stage_dir/app/build.gradle"
    run_helper patch-android-game-activity \
        "$stage_dir/love/src/main/java/org/love2d/android/GameActivity.java"
    run_helper patch-android-local-properties \
        "$stage_dir/local.properties" \
        "$ANDROID_SDK_ROOT"
}

build_love_archive() {
    local love_output="$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/love"

    rm -rf "$love_output"
    mkdir -p "$love_output"
    DELTARUNE_DDD_CH1_MOD_DIR="$DELTARUNE_DDD_CH1_MOD_DIR" \
        DELTARUNE_DDD_CH1_KRISTAL_SOURCE="${DELTARUNE_DDD_CH1_KRISTAL_SOURCE:-}" \
        DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO=1 \
        DELTARUNE_DDD_CH1_BUILD_VARIANTS=release \
        DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=0 \
        DELTARUNE_DDD_CH1_OUTPUT_DIR="$love_output" \
        DELTARUNE_DDD_CH1_NO_OPEN_DIR=1 \
        "$DELTARUNE_DDD_CH1_MOD_DIR/tools/build_standalone.sh"
    [ -s "$love_output/${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-release.love" ] || fail \
        "The release .love archive was not created"
}

build_apk() {
    local stage_dir="$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/project"
    local apk_source apk_output apksigner

    (cd "$stage_dir" && ./gradlew --no-daemon assembleEmbedNoRecordRelease)

    apk_source="$(find "$stage_dir/app/build/outputs/apk" -type f -name '*.apk' \
        -path '*/embedNoRecord/release/*' | sort | tail -n 1)"
    [ -n "$apk_source" ] || fail "Gradle completed without producing an APK"

    apk_output="$DELTARUNE_DDD_CH1_OUTPUT_DIR/${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-android.apk"
    mkdir -p "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
    cp "$apk_source" "$apk_output"
    test -s "$apk_output"
    # Use the jar directly instead of the apksigner shell wrapper: the wrapper
    # has no .bat counterpart on Windows (only apksigner.bat exists there), so
    # `java -jar` is the portable way to run it on every host.
    # java is a native Windows binary: give it a host path, not an MSYS /c/...
    # one (win_path is a no-op for already-host paths and on POSIX).
    apksigner_jar="$(win_path "$ANDROID_SDK_ROOT/build-tools/34.0.0/lib/apksigner.jar")"
    [ -f "$apksigner_jar" ] || fail \
        "Android build-tools apksigner.jar is missing: $apksigner_jar"
    java -jar "$apksigner_jar" verify "$apk_output" >/dev/null 2>&1 || fail \
        "Generated APK is not signed or failed Android signature verification: $apk_output"
    log "Created Android APK: $apk_output"
}

check_inputs
build_love_archive
ensure_android_source
stage_android_source
build_apk
open_output_dir "$DELTARUNE_DDD_CH1_OUTPUT_DIR"
