# Thrash Machine

[![license](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue)](LICENSE-APACHE) <img src="https://img.shields.io/github/repo-size/Bli-AIk/thrash-machine.svg"/> <img src="https://img.shields.io/github/last-commit/Bli-AIk/thrash-machine.svg"/>
<img src="https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge"/> <img src="https://img.shields.io/badge/Kristal-3B3B3B?style=for-the-badge"/>

> 当前状态：可作为新 Kristal Mod 的开发模板使用。

**Thrash Machine** 是一个标准 Lua Kristal v0.10 模板。它保留可运行的 starter map、Dummy 战斗和对象事件，并将简体中文语言库、开发期 object-editor、terminal-cli、Emacs 和 Helix 配置组织为可更新的子模块。

| 简体中文 | English |
| --- | --- |
| 简体中文 | [English](README_en.md) |

## 特性

- 作者维护的 Mod 代码使用 Kristal 原生 Lua 文件。
- kristal-i18n 预置英文/简体中文和系统语言自动选择。
- object-editor 仅在开发模式启用，生产包自动禁用并移除。
- terminal-cli 在开发模式下把 Kristal 调试控制台连接到当前终端，生产包自动移除。
- kristal-debug-tools 提供可复用的战斗启动调试参数，生产包自动移除。
- .emacs 和 .helix 提供项目级 Kristal/LuaLS 配置。
- release-please、Mod ZIP、release/debug .love、Windows x64 包和 SHA-256 清单。
- 可选 Android APK 打包入口，以及仅在 Android 默认启用的虚拟触摸按键库。

## 使用

### 克隆

    git clone --recurse-submodules https://github.com/Bli-AIk/thrash-machine.git
    cd thrash-machine
    git submodule update --init --recursive

模板在 mod.json 中使用 ID thrash-machine。从 GitHub 的 Use this template 创建新仓库后，应先修改该 ID、显示名称、版本和 README 徽章地址。

### 依赖

| 工具 | 用途 |
| --- | --- |
| Git | 获取模板和子模块。 |
| LÖVE 11.5 | 运行 Kristal。 |
| Kristal v0.10.0 | 本地运行与独立包基线。 |
| LuaJIT | Lua 语法检查和运行时。 |
| rsync、zip、unzip、Python 3 | 构建发行包。 |
| JDK 17、Android SDK API 34、Build Tools 34.0.0、Android NDK 25.2.9519653 | 可选 Android APK 构建。 |
| just | 运行共享 Kristal 调试启动器。 |
| Emacs 30+ 或 Helix、lua-language-server | 可选编辑器支持。 |

### 开发

    make test
    KRISTAL_ROOT=/path/to/Kristal just run

just run 也会查找常见的本地 Kristal 路径；开发模式下可直接在当前终端输入 Lua 调试命令。要在独立的干净 Kristal checkout 中跑启动 smoke test：

直接调试战斗时可以使用共享 `kristal-debug-tools` 子模块：

    just run --encounter
    just run --wave 2 --tp 50 --mercy 100
    just run --wave-force 3

`--wave` 使用敌人 wave 列表的从 1 开始的编号，也接受 wave ID；`--wave-force` 会在每轮重复该 wave。其他项目只需引用 `libraries/kristal-debug-tools` 并配置自己的 `default_encounter`。

    KRISTAL=/path/to/Kristal make test-kristal

### 编辑器

.emacs 和 .helix 是项目级配置子模块。它们提供 LuaLS、Kristal 路径和启动快捷键；设置 KRISTAL_ROOT 后即可从对应编辑器启动游戏。

## 构建与发行

    just build
    just build-mod

just build 固定使用 Kristal v0.10.0，生成 release/debug .love、Windows x64 包；它仅修改暂存引擎副本的目标 Mod、自动启动、窗口标识和 release/debug 标志。just build-mod 生成可放入 Kristal mods/ 的生产 Mod ZIP。

生产资产会保留语言库，禁用并剔除 object-editor、terminal-cli、编辑器配置、测试和构建文件。GitHub Actions 会在 PR/main 上验证构建；release-please 合并发布 PR 后，标签工作流会上传所有资产与 SHA256SUMS。

### Android

Android 构建是显式目标，不会被普通 `just build` 或发布工作流默认触发。它使用官方 LÖVE Android 11.5 工程，将 release `.love` 放入 APK，并默认使用本机 Android debug keystore 签名，使 APK 可以直接安装到设备：

    just build-android

首次构建需要 JDK 17、Android SDK API 34、Build Tools `34.0.0`、Android NDK `25.2.9519653`、Git、rsync 和可用网络。可以用官方 `sdkmanager` 安装 Android 组件：

    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
    export ANDROID_SDK_ROOT=/home/aik/Android/Sdk
    yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" --licenses
    "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
        "platforms;android-34" "build-tools;34.0.0" "ndk;25.2.9519653"

可通过环境变量覆盖应用信息：

    ANDROID_SDK_ROOT=/path/to/android-sdk \
    THRASH_MACHINE_ANDROID_APPLICATION_ID=com.example.myproject \
    THRASH_MACHINE_ANDROID_NAME="My Project" \
    THRASH_MACHINE_ANDROID_VERSION_CODE=1 \
    just build-android

官方 Android 工程会缓存到 `.build/cache/love-android-11.5`，APK 输出为 `dist/thrash-machine-android.apk`。默认签名适合本地测试，不适合发布到应用商店；正式发布时可通过以下环境变量使用自己的 keystore：

    THRASH_MACHINE_ANDROID_SIGNING_KEYSTORE=/absolute/path/release.keystore \
    THRASH_MACHINE_ANDROID_SIGNING_STORE_PASSWORD='store-password' \
    THRASH_MACHINE_ANDROID_SIGNING_KEY_ALIAS='release' \
    THRASH_MACHINE_ANDROID_SIGNING_KEY_PASSWORD='key-password' \
    just build-android

密码建议通过 CI secret 或当前 shell 环境注入，不要提交到仓库。可以设置 `THRASH_MACHINE_ANDROID_ICON` 使用一个 PNG 替换默认 LÖVE 图标。

`virtualkeyboard` library 默认只在 Android 启用，提供分离的十字按钮布局和可选摇杆布局，并把触摸转换为普通 Kristal `Input` 按键。宽屏有足够边框空间时，按键会绘制在游戏画布左右的边栏；所有布局都会在左侧外边缘约留一个按键宽、右侧约留两个按键宽，窄屏则在 640x480 画布内保持同样的边距。默认十字区域支持多点、滑动切换和斜向输入；右侧 Z 键垂直对齐在 X/C 中点，动作键也可以同时按下。它只承诺 APK 打包、LÖVE Android runtime 启动和这些基础输入；不承诺 Kristal 或 Mod 使用的所有 LÖVE API 在 Android 上兼容。要测试桌面触摸输入，可在 `mod.json` 的 `virtualkeyboard` 配置中将 `only_android` 设为 `false`。

## 提交规范

使用 KRISIS 风格的 Conventional Commits，摘要以简洁中文表达：

    feat: 添加新的 Lua 战斗波次
    fix: 修复地图切换后的对象事件
    refactor: 整理战斗模块
    docs: 补充 Lua 开发说明
    chore(main): release v0.1.0

feat 与 fix 会被 release-please 用于版本与变更日志；发布提交由自动化生成。

## 许可证

本仓库自有的 Lua 源码与文档可任选以下许可证使用：

- Apache License, Version 2.0（LICENSE-APACHE）
- MIT License（LICENSE-MIT）

Kristal starter 内容和子模块具有各自的许可边界，详见第三方声明（THIRD_PARTY.md）。
