#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DELTARUNE_DDD_CH1_MOD_DIR="${DELTARUNE_DDD_CH1_MOD_DIR:-$SCRIPT_DIR}"
DELTARUNE_DDD_CH1_MOD_DIR="$(CDPATH= cd -- "$DELTARUNE_DDD_CH1_MOD_DIR" && pwd -P)"
DELTARUNE_DDD_CH1_OUTPUT_DIR="${DELTARUNE_DDD_CH1_OUTPUT_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/dist}"
DELTARUNE_DDD_CH1_ANDROID_WORK_DIR="${DELTARUNE_DDD_CH1_ANDROID_WORK_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/android}"
DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR="${DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR:-$DELTARUNE_DDD_CH1_MOD_DIR/.build/cache/love-android-11.5}"

DELTARUNE_DDD_CH1_ANDROID_REPO="${DELTARUNE_DDD_CH1_ANDROID_REPO:-https://github.com/love2d/love-android.git}"
DELTARUNE_DDD_CH1_ANDROID_REF="${DELTARUNE_DDD_CH1_ANDROID_REF:-11.5}"
DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID="${DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID:-org.deltarune.ddd.ch1}"
DELTARUNE_DDD_CH1_ANDROID_NAME="${DELTARUNE_DDD_CH1_ANDROID_NAME:-deltarune distant, divergent dream}"
DELTARUNE_DDD_CH1_ANDROID_ORIENTATION="${DELTARUNE_DDD_CH1_ANDROID_ORIENTATION:-landscape}"
DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE="${DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE:-1}"
DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME="${DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME:-}"
DELTARUNE_DDD_CH1_ANDROID_ICON="${DELTARUNE_DDD_CH1_ANDROID_ICON:-}"
DELTARUNE_DDD_CH1_ANDROID_NDK_DIR="${DELTARUNE_DDD_CH1_ANDROID_NDK_DIR:-}"
DELTARUNE_DDD_CH1_OUTPUT_BASENAME="${DELTARUNE_DDD_CH1_OUTPUT_BASENAME:-deltarune-ddd-ch1}"

log() {
    printf '[android-build] %s\n' "$*" >&2
}

fail() {
    printf '[android-build] %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

read_mod_version() {
    python3 - "$DELTARUNE_DDD_CH1_MOD_DIR/mod.json" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'(?m)^\s*"version"\s*:\s*"([^"]+)"', text)
if not match:
    raise SystemExit("Could not find mod.json version")
version = match.group(1)
print(version[1:] if version.startswith("v") else version)
PY
}

check_inputs() {
    local java_home java_version android_sdk ndk_dir

    need_cmd git
    need_cmd java
    need_cmd python3
    need_cmd rsync
    need_cmd find

    java_home="${DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME:-${JAVA_HOME:-}}"
    if [ -n "$java_home" ]; then
        [ -x "$java_home/bin/java" ] || fail \
            "Configured Java home does not contain a Java executable: $java_home"
        export JAVA_HOME="$java_home"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi

    java_version="$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)"
    [ "$java_version" = "17" ] || fail \
        "LÖVE Android 11.5 requires JDK 17; detected ${java_version:-unknown}. Set JAVA_HOME or DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME to a JDK 17 installation."

    android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    [ -n "$android_sdk" ] || fail \
        "Set ANDROID_SDK_ROOT to an Android SDK containing API 34 and NDK 25.2.9519653"
    export ANDROID_SDK_ROOT="$android_sdk"
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

stage_android_source() {
    local stage_dir="$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/project"

    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    rsync -a --delete \
        --exclude='/.git' \
        --exclude='/.git/' \
        "$DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR/" "$stage_dir/"
    mkdir -p "$stage_dir/app/src/embed/assets"
    cp "$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/love/${DELTARUNE_DDD_CH1_OUTPUT_BASENAME}-release.love" \
        "$stage_dir/app/src/embed/assets/game.love"

    if [ -n "$DELTARUNE_DDD_CH1_ANDROID_ICON" ]; then
        [ -f "$DELTARUNE_DDD_CH1_ANDROID_ICON" ] || fail \
            "Android icon does not exist: $DELTARUNE_DDD_CH1_ANDROID_ICON"
        for density in ldpi mdpi hdpi xhdpi xxhdpi xxxhdpi; do
            mkdir -p "$stage_dir/app/src/main/res/drawable-$density"
            cp "$DELTARUNE_DDD_CH1_ANDROID_ICON" \
                "$stage_dir/app/src/main/res/drawable-$density/love.png"
        done
    fi

    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-android-properties \
        "$stage_dir/gradle.properties" \
        "$DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID" \
        "$DELTARUNE_DDD_CH1_ANDROID_NAME" \
        "$DELTARUNE_DDD_CH1_ANDROID_ORIENTATION" \
        "$DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE" \
        "$DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME"
    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-android-gradle \
        "$stage_dir/app/build.gradle"
    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-android-game-activity \
        "$stage_dir/love/src/main/java/org/love2d/android/GameActivity.java"
    python3 "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.py" patch-android-local-properties \
        "$stage_dir/local.properties" \
        "$ANDROID_SDK_ROOT"
}

build_love_archive() {
    local love_output="$DELTARUNE_DDD_CH1_ANDROID_WORK_DIR/love"

    rm -rf "$love_output"
    mkdir -p "$love_output"
    DELTARUNE_DDD_CH1_MOD_DIR="$DELTARUNE_DDD_CH1_MOD_DIR" \
        DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO=1 \
        DELTARUNE_DDD_CH1_BUILD_VARIANTS=release \
        DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=0 \
        DELTARUNE_DDD_CH1_OUTPUT_DIR="$love_output" \
        "$DELTARUNE_DDD_CH1_MOD_DIR/build_standalone.sh"
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
    apksigner="$ANDROID_SDK_ROOT/build-tools/34.0.0/apksigner"
    [ -x "$apksigner" ] || fail "Android build-tools apksigner is missing: $apksigner"
    "$apksigner" verify "$apk_output" >/dev/null 2>&1 || fail \
        "Generated APK is not signed or failed Android signature verification: $apk_output"
    log "Created Android APK: $apk_output"
}

check_inputs
build_love_archive
ensure_android_source
stage_android_source
build_apk
