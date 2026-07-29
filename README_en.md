# Thrash Machine

[![license](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue)](LICENSE-APACHE)

**Thrash Machine** is a standard Lua Kristal v0.10 template. It keeps a playable starter map, Dummy battle, and object event while wiring together Simplified Chinese localization, development-only object editing and terminal debugging, and project-local Emacs and Helix configuration.

[简体中文](README.md)

## Quick Start

    git clone --recurse-submodules https://github.com/Bli-AIk/thrash-machine.git
    cd thrash-machine
    git submodule update --init --recursive
    make test
    KRISTAL_ROOT=/path/to/Kristal just run

Battle startup debugging is provided by the `kristal-debug-tools` library submodule:

    just run --encounter
    just run --wave 2 --tp 50 --mercy 100
    just run --wave-force 3

The template uses thrash-machine as its Mod ID. Change the ID, display name, version, and README badge URLs after creating a repository from the GitHub template.

## Tooling

- Kristal v0.10.0 and LÖVE 11.5 for local runs and standalone builds.
- JDK 17, Android SDK API 34, Build Tools 34.0.0, and Android NDK 25.2.9519653 for the optional Android build.
- LuaJIT for syntax checks and runtime support.
- kristal-i18n for English and Simplified Chinese localization.
- object-editor for development-only scene editing; release packages exclude it.
- terminal-cli for interactive Lua debugging in the development terminal; release packages exclude it.
- kristal-debug-tools for reusable battle startup debugging; release packages exclude it.
- .emacs and .helix for LuaLS, Kristal paths, and launch helpers.
- An optional Android APK target and Android-only-by-default virtual touch controls.

## Builds

    just build
    just build-mod

The standalone builder stages stock Kristal v0.10.0 and changes only target-Mod startup, window identity, and release/debug flags. Production packages keep localization, disable the object editor, exclude terminal-cli, and omit development files.

### Android

Android is an explicit build target and is not included in the normal desktop build or release jobs. It uses the official LÖVE Android 11.5 project, embeds the release `.love` archive, and signs the APK with the local Android debug keystore by default so it can be installed directly on a device:

    just build-android

The first build requires JDK 17, Android SDK API 34, Build Tools `34.0.0`, Android NDK `25.2.9519653`, Git, rsync, and network access. Install the Android components with the official `sdkmanager`:

    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
    export ANDROID_SDK_ROOT=/home/aik/Android/Sdk
    yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses
    "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
        "platforms;android-34" "build-tools;34.0.0" "ndk;25.2.9519653"

Application metadata can be overridden with environment variables:

    ANDROID_SDK_ROOT=/path/to/android-sdk \
    THRASH_MACHINE_ANDROID_APPLICATION_ID=com.example.myproject \
    THRASH_MACHINE_ANDROID_NAME="My Project" \
    THRASH_MACHINE_ANDROID_VERSION_CODE=1 \
    just build-android

The Android project is cached in `.build/cache/love-android-11.5`; the APK is written to `dist/thrash-machine-android.apk`. The default signature is for local testing, not store distribution. For a release build, provide your own keystore through these environment variables:

    THRASH_MACHINE_ANDROID_SIGNING_KEYSTORE=/absolute/path/release.keystore \
    THRASH_MACHINE_ANDROID_SIGNING_STORE_PASSWORD='store-password' \
    THRASH_MACHINE_ANDROID_SIGNING_KEY_ALIAS='release' \
    THRASH_MACHINE_ANDROID_SIGNING_KEY_PASSWORD='key-password' \
    just build-android

Inject passwords through CI secrets or the current shell environment instead of committing them. Set `THRASH_MACHINE_ANDROID_ICON` to a PNG to replace the default LÖVE icon.

The `virtualkeyboard` library is enabled by default only on Android. It provides a separated directional cross and an optional joystick layout, converting touch input into normal Kristal `Input` keys. On wide screens with enough border space, the controls are drawn in the side areas outside the game canvas; every layout leaves about one button width at the left outer edge and two at the right, while narrower windows keep the same spacing inside the 640x480 canvas. The default cross supports multi-touch, sliding between directions, and diagonal input. The `z` button is vertically centered between `x` and `c`, and action buttons can be held together as well. It only covers APK packaging, starting the LÖVE Android runtime, and this basic input path; it does not guarantee that every LÖVE API used by Kristal or a Mod is Android-compatible. Set `only_android` to `false` in the `virtualkeyboard` section of `mod.json` to test it on desktop.

## License

Repository-authored Lua source and documentation are dual-licensed under Apache-2.0 (LICENSE-APACHE) or MIT (LICENSE-MIT). See third-party notices (THIRD_PARTY.md) for Kristal and submodule license boundaries.
