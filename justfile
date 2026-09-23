default: test

libs := env("DELTARUNE_DDD_CH1_OPTIONAL_LIBS", "")

# Run the Mod with a local Kristal checkout and shared debug tools.
run *args:
    @set -- {{ args }}; libs="{{ libs }}"; rest=""; for arg in "$@"; do case "$arg" in libs=*) libs="${arg#libs=}" ;; *) rest="$rest $arg" ;; esac; done; DELTARUNE_DDD_CH1_OPTIONAL_LIBS="$libs" just --justfile libraries/kristal-debug-tools/justfile run $rest

test:
    @make test

test-kristal:
    @make test-kristal

build:
    @./build_standalone.sh

build-android:
    @./build_android.sh

build-mod:
    @./.github/scripts/build_mod.sh

clean-build:
    rm -rf .build dist
