#!/usr/bin/env python3
import argparse
import re
import zipfile
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_once(text: str, pattern: str, replacement: str, path: Path, flags: int = 0) -> str:
    patched, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"Could not patch {pattern!r} in {path}")
    return patched


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def patch_lua_config(args: argparse.Namespace) -> None:
    stage_dir = Path(args.stage_dir)
    vendcust = stage_dir / "src" / "engine" / "vendcust.lua"
    conf = stage_dir / "conf.lua"

    text = read_text(vendcust)
    for pattern, replacement in {
        r"(?m)^TARGET_MOD\s*=.*$": f"TARGET_MOD = {lua_quote(args.mod_id)}",
        r"(?m)^AUTO_MOD_START\s*=.*$": "AUTO_MOD_START = true",
        r"(?m)^RELEASE_MODE\s*=.*$": f"RELEASE_MODE = {args.release_mode}",
    }.items():
        text = replace_once(text, pattern, replacement, vendcust)
    write_text(vendcust, text)

    text = read_text(conf)
    text = replace_once(
        text,
        r"(?m)^(\s*t\.identity\s*=\s*).*$",
        rf"\g<1>{lua_quote(args.identity)}",
        conf,
    )
    text = replace_once(
        text,
        r"(?m)^(\s*t\.window\.title\s*=\s*).*$",
        rf"\g<1>{lua_quote(args.title)}",
        conf,
    )
    write_text(conf, text)


def patch_mod_manifest(args: argparse.Namespace) -> None:
    manifest = Path(args.manifest)
    text = read_text(manifest)
    text = replace_once(text, r'("dev"\s*:\s*)(true|false)', rf"\g<1>{args.dev}", manifest)
    text = replace_once(
        text,
        r'("object-editor"\s*:\s*\{.*?"enabled"\s*:\s*)(true|false)',
        rf"\g<1>{args.object_editor}",
        manifest,
        flags=re.S,
    )
    write_text(manifest, text)


def set_gradle_property(text: str, key: str, value: str, path: Path) -> str:
    if "\n" in value or "\r" in value:
        raise SystemExit(f"Invalid newline in Gradle property {key!r} for {path}")

    pattern = rf"(?m)^{re.escape(key)}=.*$"
    replacement = f"{key}={value}"
    patched, count = re.subn(pattern, replacement, text, count=1)
    if count == 1:
        return patched

    if patched and not patched.endswith("\n"):
        patched += "\n"
    return patched + replacement + "\n"


def local_properties_value(value: str) -> str:
    """Escape a path for java.util.Properties, used by local.properties."""
    return (
        value.replace("\\", "\\\\")
        .replace(" ", "\\ ")
        .replace(":", "\\:")
        .replace("=", "\\=")
    )


def patch_android_local_properties(args: argparse.Namespace) -> None:
    properties = Path(args.properties)
    text = read_text(properties) if properties.exists() else ""

    text = re.sub(rf"(?m)^[ \t]*{re.escape('sdk.dir')}[ \t]*=.*(?:\n|$)", "", text)
    text = set_gradle_property(
        text, "sdk.dir", local_properties_value(args.sdk_dir), properties
    )

    write_text(properties, text)


def patch_android_properties(args: argparse.Namespace) -> None:
    properties = Path(args.properties)
    text = read_text(properties)

    for key in ("app.name", "app.name_byte_array"):
        text = re.sub(rf"(?m)^{re.escape(key)}=.*\n?", "", text)

    name = args.name
    if all(ord(char) < 128 for char in name):
        text = set_gradle_property(text, "app.name", name, properties)
    else:
        byte_array = ",".join(str(byte) for byte in name.encode("utf-8"))
        text = set_gradle_property(text, "app.name_byte_array", byte_array, properties)

    for key, value in {
        "app.application_id": args.application_id,
        "app.orientation": args.orientation,
        "app.version_code": args.version_code,
        "app.version_name": args.version_name,
    }.items():
        text = set_gradle_property(text, key, value, properties)

    write_text(properties, text)


def patch_android_gradle(args: argparse.Namespace) -> None:
    gradle = Path(args.gradle)
    text = read_text(gradle)
    original = """    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
"""
    replacement = """    def signingKeystore = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE")
    def hasCustomSigning = signingKeystore != null && !signingKeystore.isEmpty()
    def signingStorePassword = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD")
    def signingKeyAlias = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS")
    def signingKeyPassword = System.getenv("DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD")

    signingConfigs {
        if (hasCustomSigning) {
            release {
                storeFile file(signingKeystore)
                storePassword signingStorePassword
                keyAlias signingKeyAlias
                keyPassword signingKeyPassword
            }
        }
    }
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
            signingConfig = hasCustomSigning ? signingConfigs.release : signingConfigs.debug
        }
    }
"""
    if original not in text:
        raise SystemExit(f"Could not patch Android signing configuration in {gradle}")
    write_text(gradle, text.replace(original, replacement, 1))


def patch_android_game_activity(args: argparse.Namespace) -> None:
    source = Path(args.source)
    text = read_text(source)
    original = (
        "        embed = getResources().getBoolean(R.bool.embed);\n"
        "\n"
        "        if (!embed) {\n"
    )
    replacement = (
        "        embed = getResources().getBoolean(R.bool.embed);\n"
        "        // Upstream skips handleIntent() for embed builds, so initialize the\n"
        "        // asset-copy path explicitly before native LÖVE asks for the game.\n"
        "        needToCopyGameInArchive = embed;\n"
        "\n"
        "        if (!embed) {\n"
    )
    if original not in text:
        raise SystemExit(f"Could not patch embedded game initialization in {source}")
    write_text(source, text.replace(original, replacement, 1))


def patch_android_loading_touch(args: argparse.Namespace) -> None:
    source = Path(args.source)
    text = read_text(source)
    original = (
        "function Loading:onKeyPressed(key)\n"
        "    self.key_check = true\n"
        "    self.skipped = true\n"
        "    if self.loading_state == Loading.States.WAITING then\n"
        "        self:beginLoad()\n"
        "    end\n"
        "end\n\n"
        "return Loading\n"
    )
    replacement = (
        "function Loading:onKeyPressed(key)\n"
        "    self.key_check = true\n"
        "    self.skipped = true\n"
        "    if self.loading_state == Loading.States.WAITING then\n"
        "        self:beginLoad()\n"
        "    end\n"
        "end\n\n"
        "-- Android has no physical keyboard during the loading screen.\n"
        "function love.touchpressed(...)\n"
        "    local state = Kristal and Kristal.getState and Kristal.getState()\n"
        "    if state == LoadingState and state.onKeyPressed then\n"
        "        state:onKeyPressed(\"confirm\")\n"
        "    end\n"
        "end\n\n"
        "return Loading\n"
    )
    if original not in text:
        raise SystemExit(f"Could not patch Android loading touch handling in {source}")
    write_text(source, text.replace(original, replacement, 1))


def zip_dir(args: argparse.Namespace) -> None:
    output = Path(args.output)
    source = Path(args.source)
    prefix = args.prefix.strip("/")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                relative = path.relative_to(source).as_posix()
                if "__pycache__/" in f"{relative}/" or relative.endswith((".pyc", ".pyo")):
                    continue
                archive.write(path, f"{prefix}/{relative}" if prefix else relative)


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    patch_lua = commands.add_parser("patch-lua-config")
    patch_lua.add_argument("stage_dir")
    patch_lua.add_argument("mod_id")
    patch_lua.add_argument("release_mode", choices=("true", "false"))
    patch_lua.add_argument("identity")
    patch_lua.add_argument("title")
    patch_lua.set_defaults(handler=patch_lua_config)

    patch_manifest = commands.add_parser("patch-mod-manifest")
    patch_manifest.add_argument("manifest")
    patch_manifest.add_argument("dev", choices=("true", "false"))
    patch_manifest.add_argument("object_editor", choices=("true", "false"))
    patch_manifest.set_defaults(handler=patch_mod_manifest)

    patch_android = commands.add_parser("patch-android-properties")
    patch_android.add_argument("properties")
    patch_android.add_argument("application_id")
    patch_android.add_argument("name")
    patch_android.add_argument("orientation")
    patch_android.add_argument("version_code")
    patch_android.add_argument("version_name")
    patch_android.set_defaults(handler=patch_android_properties)

    patch_android_local = commands.add_parser("patch-android-local-properties")
    patch_android_local.add_argument("properties")
    patch_android_local.add_argument("sdk_dir")
    patch_android_local.set_defaults(handler=patch_android_local_properties)

    patch_android_gradle_command = commands.add_parser("patch-android-gradle")
    patch_android_gradle_command.add_argument("gradle")
    patch_android_gradle_command.set_defaults(handler=patch_android_gradle)

    patch_android_activity_command = commands.add_parser("patch-android-game-activity")
    patch_android_activity_command.add_argument("source")
    patch_android_activity_command.set_defaults(handler=patch_android_game_activity)

    patch_android_loading_command = commands.add_parser("patch-android-loading-touch")
    patch_android_loading_command.add_argument("source")
    patch_android_loading_command.set_defaults(handler=patch_android_loading_touch)

    zip_command = commands.add_parser("zip-dir")
    zip_command.add_argument("output")
    zip_command.add_argument("source")
    zip_command.add_argument("prefix", nargs="?", default="")
    zip_command.set_defaults(handler=zip_dir)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
