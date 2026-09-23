#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd -P)
fake_engine=$(mktemp -d)
launcher_tmp=''
touch "$fake_engine/main.lua"
cleanup() {
    rm -rf "$fake_engine" "$launcher_tmp"
}
trap cleanup EXIT HUP INT TERM
engine_root=${KRISTAL_ROOT:-$fake_engine}

run_dry() {
    KRISTAL_ROOT="$engine_root" \
    KRISTAL_DEBUG_TOOLS_DRY_RUN=1 \
    just --justfile "$root/justfile" run "$@"
}

output=$(run_dry --wave 2 --tp 50 --mercy 100)
printf '%s\n' "$output" | grep -Fqx "mod_root=$root"
printf '%s\n' "$output" | grep -Fqx 'mod_id=deltarune-ddd-ch1'
printf '%s\n' "$output" | grep -F -- '--wave 2' >/dev/null
printf '%s\n' "$output" | grep -F -- '--tp 50' >/dev/null
printf '%s\n' "$output" | grep -F -- '--mercy 100' >/dev/null

output=$(run_dry --encounter --initial-tp=25 --initial-mercy=75)
printf '%s\n' "$output" | grep -F -- '--encounter' >/dev/null
printf '%s\n' "$output" | grep -F -- '--tp 25' >/dev/null
printf '%s\n' "$output" | grep -F -- '--mercy 75' >/dev/null

output=$(run_dry --wave-force 3)
printf '%s\n' "$output" | grep -F -- '--wave-force 3' >/dev/null

output=$(run_dry --lang zh-hans)
printf '%s\n' "$output" | grep -F -- '--lang zh-hans' >/dev/null

output=$(run_dry --language=en)
printf '%s\n' "$output" | grep -F -- '--lang en' >/dev/null

output=$(run_dry -l zh-hans)
printf '%s\n' "$output" | grep -F -- '--lang zh-hans' >/dev/null

output=$(run_dry -- --custom value)
printf '%s\n' "$output" | grep -F -- '--custom value' >/dev/null

if run_dry --tp >/dev/null 2>&1; then
    printf '%s\n' 'missing-value validation failed' >&2
    exit 1
fi

if run_dry --unknown >/dev/null 2>&1; then
    printf '%s\n' 'unknown-option validation failed' >&2
    exit 1
fi

if run_dry --language >/dev/null 2>&1; then
    printf '%s\n' 'language missing-value validation failed' >&2
    exit 1
fi

# tools/just must choose its sidecar by the detected engine VERSION. Simulate
# Git Bash and a release server locally so this never needs network access.
launcher_tmp=$(mktemp -d)
launcher_bin="$launcher_tmp/bin"
mkdir -p "$launcher_bin"
printf '%s\n' '#!/bin/sh' \
    'case "$1" in' \
    '  -s) printf "%s\\n" MINGW64_NT ;;' \
    '  -m) printf "%s\\n" x86_64 ;;' \
    'esac' > "$launcher_bin/uname"
printf '%s\n' '#!/bin/sh' \
    'set -eu' \
    'out=' \
    'url=' \
    'while [ "$#" -gt 0 ]; do' \
    '  case "$1" in' \
    '    --output) out=$2; shift 2 ;;' \
    '    --fail|--location) shift ;;' \
    '    *) url=$1; shift ;;' \
    '  esac' \
    'done' \
    'printf "%s\\n" "$url" >> "$CURL_LOG"' \
    'case "$out" in' \
    '  *checksums*)' \
    '    set -- "$(dirname "$out")"/kristal-run-windows-x64.exe.tmp.*' \
    '    hash=$(sha256sum "$1" | awk "{print \$1}")' \
    '    printf "%s  kristal-run-windows-x64.exe\\n" "$hash" > "$out"' \
    '    ;;' \
    '  *)' \
    '    printf "%s\\n" "#!/bin/sh" "printf '\''%s\\n'\'' \"\$*\" > \"\$SIDE_LOG\"" > "$out"' \
    '    chmod +x "$out"' \
    '    ;;' \
    'esac' > "$launcher_bin/curl"
chmod +x "$launcher_bin/uname" "$launcher_bin/curl"

run_fixed_gui_release_case() {
    version=$1
    tag=$2
    case_dir="$launcher_tmp/$version"
    engine_dir="$case_dir/Kristal"
    curl_log="$case_dir/curl.log"
    side_log="$case_dir/side.log"
    mkdir -p "$engine_dir/src"
    : > "$engine_dir/main.lua"
    : > "$engine_dir/src/kristal.lua"
    printf '%s\n' "$version" > "$engine_dir/VERSION"
    : > "$curl_log"
    CURL_LOG="$curl_log" SIDE_LOG="$side_log" KRISTAL_ROOT="$engine_dir" JUST= KRISTAL_RUN= \
        PATH="$launcher_bin:/usr/bin:/bin" "$root/tools/just" build
    grep -Fqx "https://github.com/Bli-AIk/kristal-debug-tools-gui/releases/download/$tag/kristal-run-windows-x64.exe" "$curl_log"
    grep -Fqx "https://github.com/Bli-AIk/kristal-debug-tools-gui/releases/download/$tag/checksums-windows-x64.txt" "$curl_log"
    grep -Fqx "just-task $root/justfile build" "$side_log"
    grep -Fqx "$tag" "$engine_dir/.tools/gui/version.txt"

    # The GUI launcher writes version.txt with CRLF. Git Bash must still recognize the
    # matching cached tag rather than downloading it again.
    printf '%s\r\n' "$tag" > "$engine_dir/.tools/gui/version.txt"
    : > "$curl_log"
    CURL_LOG="$curl_log" SIDE_LOG="$side_log" KRISTAL_ROOT="$engine_dir" JUST= KRISTAL_RUN= \
        PATH="$launcher_bin:/usr/bin:/bin" "$root/tools/just" build
    test ! -s "$curl_log"

    # A version marker from another release must force a re-download instead
    # of accepting an otherwise valid sidecar cache.
    printf '%s\n' 'v0.0.0' > "$engine_dir/.tools/gui/version.txt"
    : > "$curl_log"
    CURL_LOG="$curl_log" SIDE_LOG="$side_log" KRISTAL_ROOT="$engine_dir" JUST= KRISTAL_RUN= \
        PATH="$launcher_bin:/usr/bin:/bin" "$root/tools/just" build
    grep -Fqx "https://github.com/Bli-AIk/kristal-debug-tools-gui/releases/download/$tag/kristal-run-windows-x64.exe" "$curl_log"
}

run_fixed_gui_release_case 0.10.0 v0.1.5
run_fixed_gui_release_case v0.10.0 v0.1.5
run_fixed_gui_release_case 0.11.0-dev v0.2.0
run_fixed_gui_release_case v0.11.0-dev v0.2.0

unknown_engine="$launcher_tmp/unknown/Kristal"
unknown_log="$launcher_tmp/unknown/curl.log"
mkdir -p "$unknown_engine/src"
: > "$unknown_engine/main.lua"
: > "$unknown_engine/src/kristal.lua"
printf '%s\n' '0.12.0' > "$unknown_engine/VERSION"
: > "$unknown_log"
if CURL_LOG="$unknown_log" SIDE_LOG="$launcher_tmp/unknown/side.log" KRISTAL_ROOT="$unknown_engine" JUST= KRISTAL_RUN= \
    PATH="$launcher_bin:/usr/bin:/bin" "$root/tools/just" build >/dev/null 2>&1; then
    printf '%s\n' 'unsupported Kristal VERSION unexpectedly launched tools/just' >&2
    exit 1
fi
test ! -s "$unknown_log"

explicit_run="$launcher_tmp/explicit-kristal-run"
explicit_log="$launcher_tmp/explicit.log"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$*" > "$SIDE_LOG"' > "$explicit_run"
chmod +x "$explicit_run"
: > "$unknown_log"
CURL_LOG="$unknown_log" SIDE_LOG="$explicit_log" KRISTAL_ROOT= DELTARUNE_DDD_CH1_KRISTAL_DIR= JUST= KRISTAL_RUN="$explicit_run" \
    PATH="$launcher_bin:/usr/bin:/bin" "$root/tools/just" build
grep -Fqx "just-task $root/justfile build" "$explicit_log"
test ! -s "$unknown_log"

grep -F 'set "GUI_LAUNCHER=%~dp0libraries\kristal-debug-tools\gui.cmd"' "$root/gui.cmd" >/dev/null
grep -F 'call "%GUI_LAUNCHER%" %*' "$root/gui.cmd" >/dev/null
gui_launcher="$root/libraries/kristal-debug-tools/gui.cmd"
grep -F 'set "GUI_RELEASE_TAG=v0.1.5"' "$gui_launcher" >/dev/null
grep -F 'set "GUI_RELEASE_TAG=v0.2.0"' "$gui_launcher" >/dev/null
if grep -F '/releases/latest/' "$gui_launcher" >/dev/null; then
    printf '%s\n' 'GUI launcher must not download the latest release' >&2
    exit 1
fi
if grep -F 'Get-FileHash' "$gui_launcher" >/dev/null; then
    printf '%s\n' 'GUI launcher must not require Get-FileHash' >&2
    exit 1
fi

printf '%s\n' 'template debug-tools smoke: PASS'
