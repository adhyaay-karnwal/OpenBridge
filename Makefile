.PHONY: bootstrap web-lint web-typecheck web-test web-build web-check sandbox-test macos-build check

bootstrap:
	git submodule update --init --recursive
	cd web && yarn install --immutable

web-lint:
	cd web && yarn lint

web-typecheck:
	cd web && yarn typecheck

web-test:
	cd web && yarn test

web-build:
	cd web && yarn build:embedded

web-check: web-lint web-typecheck web-test web-build

sandbox-test:
	make -C sandbox-vm go-test

macos-build:
	cd macos && BUILD_CONFIGURATION=UnsignedDebug bash DevKit/Scripts/workspace_build_debug.sh

check: web-check sandbox-test
