# Run the project with a local Kristal checkout and shared debug tools.
# zh_hans: 用本地 Kristal 引擎启动项目（带共享调试工具）
default: test

# Optional-library override for this launch only; mod.json is never modified.
# Comma-separated library ids or the alias a lib.json declares; a "-" prefix
# forces one off. Unknown names are reported with every valid name.
# `just run libs=...` is the spelling to reach for; it is read out of the
# launcher arguments by the run recipe below. `just libs=... run` and the
# DELTARUNE_DDD_CH1_OPTIONAL_LIBS environment variable work too.
# e.g. just run libs=mgr            start with MagicalGlassRedux enabled
#      just run libs=mgr,umr -w 3   both packs, plus the usual debug arguments
#      just run libs=-kristalI18n   any library, not just the optional pair
# zh_hans: 仅本次启动生效的子库开关（不改 mod.json）。逗号分隔，可写 lib.json 里声明的
# zh_hans: alias 或完整 id；"-" 前缀表示强制关闭（要 umr 时会自动带上它依赖的 MGR）。
# zh_hans: 推荐写成 just run libs=mgr（由下面的 run recipe 从启动参数里读出来），
# zh_hans: 也可以写成 just libs=mgr run，或用环境变量。
libs := env("DELTARUNE_DDD_CH1_OPTIONAL_LIBS", "")

# Run the project with debug launcher arguments.
# zh_hans: 启动项目，可带调试参数（如 -w 波次、-tp 初始 TP）
# libs= is pulled out of the arguments here rather than left to just's own
# `name=value` variable syntax, which only applies BEFORE the recipe name —
# `just run libs=mgr` would otherwise sail through as a stray engine argument.
# zh_hans: 这里手动从参数里挑出 libs=：just 自己的 name=value 语法只认 recipe 名之前的位置，
# zh_hans: 写成 just run libs=mgr 的话会被当成普通启动参数透传给引擎而静默失效。
run *args:
    @set -- {{ args }}; \
    libs="{{ libs }}"; rest=""; \
    for arg in "$@"; do \
        case "$arg" in \
            libs=*) libs="${arg#libs=}" ;; \
            *) rest="$rest $arg" ;; \
        esac; \
    done; \
    DELTARUNE_DDD_CH1_OPTIONAL_LIBS="$libs" just --justfile libraries/kristal-debug-tools/justfile run $rest

# Run the debug-tools GUI (end users: auto-downloads/updates release binaries).
# zh_hans: 启动调试工具图形界面（自动检测并下载最新 release，无需 just/Rust/Node）
gui:
    @just --justfile libraries/kristal-debug-tools/justfile gui

# Run the debug-tools GUI from source (clones the GUI repo on demand).
# zh_hans: 源码模式运行调试工具图形界面（GUI 仓库按需 clone）
gui-dev:
    @just --justfile libraries/kristal-debug-tools/justfile gui-dev

# Run the debug-tools GUI from source with a Rust release build.
# zh_hans: 源码模式运行调试工具图形界面（Rust release 构建）
gui-dev-release:
    @just --justfile libraries/kristal-debug-tools/justfile gui-dev-release

# Run the project's test suite.
# zh_hans: 运行项目测试
test:
    @make test

# Run Kristal's own test suite.
# zh_hans: 运行 Kristal 引擎测试
test-kristal:
    @make test-kristal

# Build .love only.
# zh_hans: 只打包 .love
build-love:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build.ps1\" love" } else { "DELTARUNE_DDD_CH1_BUILD_LOVE=1 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=0 bash ./tools/build_standalone.sh" } }}

# Build Windows only.
# zh_hans: 只打包 Windows
build-win:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build.ps1\" win" } else { "DELTARUNE_DDD_CH1_BUILD_LOVE=0 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=1 bash ./tools/build_standalone.sh" } }}

# Build .love + Windows (original behavior).
# zh_hans: 同时打包 .love 和 Windows（老用法）
build:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build.ps1\" all" } else { "DELTARUNE_DDD_CH1_BUILD_LOVE=1 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=1 bash ./tools/build_standalone.sh" } }}

# Compile the Android APK from source (full build; needs JDK 17 + Android SDK API 34 + NDK 25.2.9519653).
# A missing JDK 17 or Android SDK (API 34 + build-tools 34.0.0 + NDK 25.2.9519653) is
# auto-downloaded into the shared tools dir next to the Kristal engine on first use
# (<kristal-root>/.tools/jdk17 / <kristal-root>/.tools/android-sdk; project-root .tools as fallback).
# Uses the pinned Kristal commit by default; set DELTARUNE_DDD_CH1_KRISTAL_SOURCE=ask
# to choose a local path, tag, commit, or branch interactively.
# zh_hans: 编译构建 Android APK（完整构建，需要 JDK 17 + Android SDK API 34 + NDK 25.2.9519653；缺 JDK/SDK 时首次自动下载到 Kristal 根 .tools/jdk17 / .tools/android-sdk，无引擎时回退 project 根 .tools；默认使用固定 Kristal commit；设 DELTARUNE_DDD_CH1_KRISTAL_SOURCE=ask 可交互选择本地路径、tag、commit 或分支）
build-android:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build_android.ps1\" compile" } else { "bash ./tools/build_android.sh" } }}

# Wrap-build a quick Android APK (official LÖVE shell + game.love, re-aligned and re-signed).
# Needs no Android SDK/NDK; JDK 17 is auto-downloaded into the shared tools dir
# when missing (see build-android). The normal Git/Kristal source requirement still applies;
# build-tools are downloaded automatically. Faster, but cannot change package id/icon/name and
# cannot be published on Google Play.
# zh_hans: 套包构建 Android APK（官方 LÖVE 壳 + game.love，重对齐并重签名；不需 Android SDK/NDK，缺 JDK 17 时自动下载到 Kristal 根 .tools/jdk17；仍需常规 Git/Kristal 源；不能改包名/图标/名称，不能上 Google Play）
build-android-wrap:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build_android.ps1\" wrap" } else { "bash ./tools/build_android_wrap.sh" } }}

# Build the project-only distribution (recipe name retained for Kristal compatibility).
# zh_hans: 构建项目单包分发版（recipe 名称为兼容 Kristal 保留）
build-mod:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + justfile_directory() + "/tools/build.ps1\" mod" } else { "bash ./.github/scripts/build_mod.sh" } }}

# Remove build artifacts.
# zh_hans: 清理构建产物
clean-build:
    @{{ if os() == "windows" { "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"Remove-Item -LiteralPath '.build','dist' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path 'dist-*' -Recurse -Force -ErrorAction SilentlyContinue\"" } else { "rm -rf .build dist dist-*" } }}
