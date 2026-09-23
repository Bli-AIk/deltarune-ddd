KRISTAL ?=

.PHONY: test test-static test-debug-tools test-ddd-3d test-kristal build build-love build-win build-android build-android-wrap

test: test-static test-debug-tools test-ddd-3d

test-static:
	sh .github/scripts/static-smoke.sh
	luajit tests/optional_libraries.lua
	luajit tests/i18n_item_key_api.lua
	luajit tests/library_enabled_announce.lua
	luajit tests/i18n_console_segments.lua
	luajit libraries/terminal-cli/tests/ansi_color.lua
	sh tests/build_helper_manifest.sh
	if command -v pwsh >/dev/null 2>&1; then pwsh -NoProfile -File tests/windows_build.ps1; else printf '%s\n' 'pwsh unavailable: skipping Windows build smoke'; fi
	find . -path ./.git -prune -o -path ./.emacs -prune -o -path ./.helix -prune -o \
		-path ./libraries -prune -o -path ./.build -prune -o -path ./dist -prune -o \
		-path ./.worktrees -prune -o -type f -name '*.lua' -print0 | \
		xargs -0 -I{} luajit -b -l {} >/dev/null
	find libraries/kristal-i18n \
		-type f -name '*.lua' -print0 | xargs -0 -I{} luajit -b -l {} >/dev/null

test-debug-tools:
	sh .github/scripts/template-justfile-smoke.sh

test-ddd-3d:
	luajit libraries/ddd-3d/tests/material_contract.lua

test-kristal:
	KRISTAL="$${KRISTAL:-$$(sh .github/scripts/find-kristal.sh 2>/dev/null)}" sh .github/scripts/run-kristal-smoke.sh

build-love:
	DELTARUNE_DDD_CH1_BUILD_LOVE=1 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=0 ./tools/build_standalone.sh

build-win:
	DELTARUNE_DDD_CH1_BUILD_LOVE=0 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=1 ./tools/build_standalone.sh

build:
	DELTARUNE_DDD_CH1_BUILD_LOVE=1 DELTARUNE_DDD_CH1_BUILD_WINDOWS_EXE=1 ./tools/build_standalone.sh

build-android:
	./tools/build_android.sh

build-android-wrap:
	./tools/build_android_wrap.sh
