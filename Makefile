KRISTAL ?=

.PHONY: test test-static test-debug-tools test-ddd-3d test-kristal build-android

test: test-static test-debug-tools test-ddd-3d

test-static:
	luajit tests/optional_libraries.lua
	luajit tests/i18n_console_segments.lua
	luajit tests/library_enabled_announce.lua
	sh .github/scripts/static-smoke.sh
	find . -path ./.git -prune -o -path ./.emacs -prune -o -path ./.helix -prune -o \
		-path ./libraries -prune -o -path ./.build -prune -o -path ./dist -prune -o \
		-path ./.worktrees -prune -o -type f -name '*.lua' -exec \
		luajit -b {} /dev/null \;

test-debug-tools:
	sh .github/scripts/template-justfile-smoke.sh

test-ddd-3d:
	luajit libraries/ddd-3d/tests/material_contract.lua

test-kristal:
	KRISTAL="$(KRISTAL)" sh .github/scripts/run-kristal-smoke.sh

build-android:
	./build_android.sh
