SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
APP_DIR := $(ROOT_DIR)/chronosync
RELAY_DIR := $(ROOT_DIR)/relay
MACOS_RELEASE_APP := $(APP_DIR)/build/macos/Build/Products/Release/ChronoSync.app

FLUTTER ?= flutter
DART ?= dart
NPM ?= npm

DEVICE ?=
EMULATOR ?=
IOS_SIMULATOR_ID ?=
TEST ?=
TEST_ARGS ?=
RELAY_URL ?=
WEB_URL ?=
WEB_PORT ?= 8080
CONFIRM_DEPLOY ?= 0

APP_DEFINES = \
	$(if $(strip $(RELAY_URL)),--dart-define=CHRONOSYNC_RELAY_URL="$(RELAY_URL)") \
	$(if $(strip $(WEB_URL)),--dart-define=CHRONOSYNC_WEB_URL="$(WEB_URL)")
DEVICE_ARG = $(if $(strip $(DEVICE)),-d "$(DEVICE)")

.NOTPARALLEL: build check check-app ci ci-native

.PHONY: \
	help makefile-check setup install app-deps relay-deps outdated doctor devices \
	emulators launch-emulator generate generate-watch nearby-client \
	nearby-client-check drift-worker drift-worker-check branding-assets \
	branding-assets-check format format-check \
	analyze lint test test-all \
	test-flutter test-focus tdd test-coverage test-browser test-native \
	test-ios-native test-macos-native relay-test relay-test-watch relay-typecheck \
	relay-check build build-native build-web build-web-debug build-ios-simulator \
	sanitize-web-release verify-web-release \
	build-ios-release build-macos-debug build-macos-release verify-macos-release \
	run run-web run-macos run-ios ios-simulators ios-simulator simulator \
	macos-configure relay-dev relay-dev-https relay-deploy check-app check-relay check ci \
	ci-native clean clean-codegen

help: ## Show available targets and configuration variables.
	@echo "ChronoSync development commands"
	@echo
	@awk 'BEGIN {FS = ":.*## ";} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Common overrides:"
	@echo "  DEVICE=<flutter-device-id>       Device used by make run"
	@echo "  IOS_SIMULATOR_ID=<udid>          Simulator used by iOS targets"
	@echo "  TEST=test/path/file_test.dart    Focused Flutter test"
	@echo "  TEST_ARGS='--name pattern'       Extra flutter test arguments"
	@echo "  RELAY_URL=https://...            Online relay compile-time URL"
	@echo "  WEB_URL=https://...              Public PWA compile-time URL"
	@echo "  WEB_PORT=8080                    Chrome development port"

makefile-check: ## Dry-run the primary recipes to validate Makefile wiring.
	@targets="setup generate nearby-client drift-worker format-check analyze test test-native build run-web run-macos run-ios ios-simulator relay-dev relay-dev-https ci ci-native clean"; \
	for target in $$targets; do \
		$(MAKE) --no-print-directory --dry-run "$$target" >/dev/null; \
	done
	@echo "Makefile recipes are valid."

setup: app-deps relay-deps ## Install all locked app and relay dependencies.

install: setup ## Alias for setup.

app-deps: ## Install Flutter and Dart dependencies.
	cd "$(APP_DIR)" && $(FLUTTER) pub get

relay-deps: ## Install locked relay dependencies.
	cd "$(RELAY_DIR)" && $(NPM) ci

outdated: ## Report outdated Flutter and relay dependencies.
	cd "$(APP_DIR)" && $(FLUTTER) pub outdated
	cd "$(RELAY_DIR)" && $(NPM) outdated || true

doctor: ## Show Flutter, Xcode, CocoaPods, Node, and connected-tool health.
	$(FLUTTER) doctor -v
	@node --version
	@$(NPM) --version

devices: ## List devices recognized by Flutter.
	cd "$(APP_DIR)" && $(FLUTTER) devices

emulators: ## List emulators recognized by Flutter.
	cd "$(APP_DIR)" && $(FLUTTER) emulators

launch-emulator: ## Launch EMULATOR=<flutter-emulator-id>.
	@test -n "$(EMULATOR)" || { echo "Set EMULATOR to an ID from 'make emulators'." >&2; exit 2; }
	cd "$(APP_DIR)" && $(FLUTTER) emulators --launch "$(EMULATOR)"

generate: ## Generate Drift and Mockito sources.
	cd "$(APP_DIR)" && $(DART) run build_runner build --delete-conflicting-outputs

generate-watch: ## Regenerate Dart sources continuously while editing.
	cd "$(APP_DIR)" && $(DART) run build_runner watch --delete-conflicting-outputs

nearby-client: ## Rebuild the browser client bundled by the iPhone host.
	cd "$(APP_DIR)" && $(DART) compile js tool/nearby_client/main.dart -O4 --no-source-maps \
		-o assets/nearby_client/client.js
	rm -f "$(APP_DIR)/assets/nearby_client/client.js.deps"

nearby-client-check: ## Verify the bundled nearby client matches its Dart source.
	@temp_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$temp_dir"' EXIT; \
	cd "$(APP_DIR)"; \
	$(DART) compile js tool/nearby_client/main.dart -O4 --no-source-maps -o "$$temp_dir/client.js"; \
	cmp "$$temp_dir/client.js" assets/nearby_client/client.js

drift-worker: ## Rebuild the web worker used by Drift's browser database.
	cd "$(APP_DIR)" && $(DART) compile js web/drift_worker.dart --no-source-maps \
		-o web/drift_worker.js
	rm -f "$(APP_DIR)/web/drift_worker.js.deps"

drift-worker-check: ## Verify the bundled Drift worker matches its Dart source.
	@temp_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$temp_dir"' EXIT; \
	cd "$(APP_DIR)"; \
	$(DART) compile js web/drift_worker.dart --no-source-maps -o "$$temp_dir/drift_worker.js"; \
	cmp "$$temp_dir/drift_worker.js" web/drift_worker.js

branding-assets: ## Regenerate native and web icons from the brand source SVG.
	cd "$(APP_DIR)" && bash tool/branding/generate_assets.sh

branding-assets-check: ## Verify committed icons match the brand source SVG.
	@temp_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$temp_dir"' EXIT; \
	cd "$(APP_DIR)"; \
	bash tool/branding/generate_assets.sh "$$temp_dir"; \
	for path in \
		ios/Runner/Assets.xcassets/AppIcon.appiconset \
		ios/Runner/Assets.xcassets/LaunchImage.imageset \
		macos/Runner/Assets.xcassets/AppIcon.appiconset \
		web/icons; do \
		for generated in "$${temp_dir}/$$path"/*.png; do \
			cmp "$$generated" "$(APP_DIR)/$$path/$$(basename "$$generated")"; \
		done; \
	done; \
	cmp "$$temp_dir/web/favicon.png" "$(APP_DIR)/web/favicon.png"

format: ## Format app source, tests, and development tools.
	cd "$(APP_DIR)" && $(DART) format lib test tool

format-check: ## Fail when Dart files are not formatted.
	cd "$(APP_DIR)" && $(DART) format --output=none --set-exit-if-changed lib test tool

analyze: generate ## Run Flutter's analyzer and lint rules.
	cd "$(APP_DIR)" && $(FLUTTER) analyze

lint: format-check analyze relay-typecheck ## Run formatting, Dart analysis, and TypeScript checks.

test: test-flutter test-browser relay-test ## Run the normal app, browser, and relay test suites.

test-all: test test-native ## Run all automated suites, including native Apple tests.

test-flutter: generate ## Run the complete Flutter VM test suite.
	cd "$(APP_DIR)" && $(FLUTTER) test --reporter compact $(TEST_ARGS)

test-focus: generate ## Run one Flutter test selected with TEST=<path>.
	@test -n "$(TEST)" || { echo "Set TEST, for example TEST=test/domain/live_session_test.dart." >&2; exit 2; }
	cd "$(APP_DIR)" && $(FLUTTER) test "$(TEST)" $(TEST_ARGS)

tdd: test-focus ## Alias for a focused red-green-refactor test run.

test-coverage: generate ## Run Flutter tests and write coverage/lcov.info.
	cd "$(APP_DIR)" && $(FLUTTER) test --coverage $(TEST_ARGS)

test-browser: generate ## Run browser-specific archive and portability tests in Chrome.
	cd "$(APP_DIR)" && $(FLUTTER) test --platform chrome \
		test/data/portability/bounded_zip_entry_decoder_test.dart \
		test/data/portability/portability_file_service_test.dart \
		test/data/portability/plan_archive_service_test.dart \
		test/core/platform/display_fullscreen_web_test.dart \
		$(TEST_ARGS)

test-native: test-ios-native test-macos-native ## Run native iOS and macOS XCTest suites.

test-ios-native: build-ios-simulator ## Run RunnerTests on an available iPhone simulator.
	@simulator_id="$(IOS_SIMULATOR_ID)"; \
	if [[ -z "$$simulator_id" ]]; then \
		simulator_id="$$(xcrun simctl list devices available | awk -F '[()]' '/^[[:space:]]+iPhone/ { print $$2; exit }')"; \
	fi; \
	test -n "$$simulator_id" || { echo "No available iPhone simulator found." >&2; exit 1; }; \
	cd "$(APP_DIR)"; \
	xcodebuild test -quiet \
		-workspace ios/Runner.xcworkspace \
		-scheme Runner \
		-configuration Debug \
		-destination "platform=iOS Simulator,id=$$simulator_id" \
		CODE_SIGNING_ALLOWED=NO

macos-configure: generate ## Configure the macOS Xcode workspace for native tests.
	cd "$(APP_DIR)" && $(FLUTTER) build macos --debug --config-only $(APP_DEFINES)

test-macos-native: macos-configure ## Run the macOS RunnerTests XCTest suite.
	cd "$(APP_DIR)" && xcodebuild test \
		-workspace macos/Runner.xcworkspace \
		-scheme Runner \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO

relay-test: ## Run relay Vitest tests once.
	cd "$(RELAY_DIR)" && $(NPM) test

relay-test-watch: ## Run relay Vitest in watch mode.
	cd "$(RELAY_DIR)" && $(NPM) run test:watch

relay-typecheck: ## Type-check the Cloudflare Worker relay.
	cd "$(RELAY_DIR)" && $(NPM) run typecheck

relay-check: ## Run relay type-checking and tests.
	cd "$(RELAY_DIR)" && $(NPM) run check

build: build-web build-ios-simulator build-macos-release ## Build all MVP targets on macOS.

build-native: build-ios-simulator build-macos-release ## Build iOS simulator and native Mac targets.

build-web: generate ## Build the release web/PWA application.
	rm -rf "$(APP_DIR)/build/web"
	cd "$(APP_DIR)" && $(FLUTTER) build web --release $(APP_DEFINES)
	$(MAKE) --no-print-directory sanitize-web-release
	$(MAKE) --no-print-directory verify-web-release

sanitize-web-release: ## Remove compiler metadata from the PWA output.
	cd "$(APP_DIR)" && $(DART) run tool/release/release_artifact_verifier.dart --sanitize build/web

verify-web-release: ## Reject source maps and local build paths in the PWA output.
	cd "$(APP_DIR)" && $(DART) run tool/release/release_artifact_verifier.dart build/web

build-web-debug: generate ## Build a debug web application.
	cd "$(APP_DIR)" && $(FLUTTER) build web --debug $(APP_DEFINES)

build-ios-simulator: generate ## Build the debug iOS Simulator application.
	cd "$(APP_DIR)" && $(FLUTTER) build ios --debug --simulator $(APP_DEFINES)

build-ios-release: generate ## Build a signed iOS release using local Xcode settings.
	cd "$(APP_DIR)" && $(FLUTTER) build ios --release $(APP_DEFINES)

build-macos-debug: generate ## Build the debug native Mac application.
	cd "$(APP_DIR)" && $(FLUTTER) build macos --debug $(APP_DEFINES)

build-macos-release: generate ## Build the release native Mac application.
	rm -rf "$(MACOS_RELEASE_APP)"
	cd "$(APP_DIR)" && $(FLUTTER) build macos --release $(APP_DEFINES)
	$(MAKE) --no-print-directory verify-macos-release

verify-macos-release: ## Verify the release app's signature and sandbox entitlements.
	@app="$(MACOS_RELEASE_APP)"; \
	test -d "$$app" || { echo "Build the Mac release first with 'make build-macos-release'." >&2; exit 2; }; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.app-sandbox' "$(APP_DIR)/macos/Runner/Release.entitlements")" = "true"; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.network.client' "$(APP_DIR)/macos/Runner/Release.entitlements")" = "true"; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.files.user-selected.read-write' "$(APP_DIR)/macos/Runner/Release.entitlements")" = "true"; \
	plutil -extract NSLocalNetworkUsageDescription raw "$(APP_DIR)/macos/Runner/Info.plist" >/dev/null; \
	codesign --verify --deep --strict --verbose=2 "$$app" || { \
		status=$$?; \
		echo "Mac release signature verification failed." >&2; \
		exit $$status; \
	}; \
	entitlements="$$(mktemp)"; \
	trap 'rm -f "$$entitlements"' EXIT; \
	codesign --display --entitlements - --xml "$$app" > "$$entitlements"; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.app-sandbox' "$$entitlements")" = "true"; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.network.client' "$$entitlements")" = "true"; \
	test "$$('/usr/libexec/PlistBuddy' -c 'Print :com.apple.security.files.user-selected.read-write' "$$entitlements")" = "true"; \
	echo "Mac release signature and entitlements are valid."

run: generate ## Run Flutter on DEVICE=<id>, or prompt when DEVICE is omitted.
	cd "$(APP_DIR)" && $(FLUTTER) run $(DEVICE_ARG) $(APP_DEFINES)

run-web: generate ## Run the app in Chrome.
	cd "$(APP_DIR)" && $(FLUTTER) run -d chrome --web-port="$(WEB_PORT)" $(APP_DEFINES)

run-macos: generate ## Run the native Mac app.
	cd "$(APP_DIR)" && $(FLUTTER) run -d macos $(APP_DEFINES)

run-ios: generate ## Boot an iPhone simulator and run the app on it.
	@simulator_id="$(IOS_SIMULATOR_ID)"; \
	if [[ -z "$$simulator_id" ]]; then \
		simulator_id="$$(xcrun simctl list devices available | awk -F '[()]' '/^[[:space:]]+iPhone/ { print $$2; exit }')"; \
	fi; \
	test -n "$$simulator_id" || { echo "No available iPhone simulator found." >&2; exit 1; }; \
	xcrun simctl boot "$$simulator_id" 2>/dev/null || true; \
	open -a Simulator; \
	xcrun simctl bootstatus "$$simulator_id" -b; \
	cd "$(APP_DIR)"; \
	$(FLUTTER) run -d "$$simulator_id" $(APP_DEFINES)

ios-simulators: ## List available iPhone simulators and their UDIDs.
	@xcrun simctl list devices available | awk '/^[[:space:]]+iPhone/'

ios-simulator: ## Boot and open IOS_SIMULATOR_ID, or the first available iPhone.
	@simulator_id="$(IOS_SIMULATOR_ID)"; \
	if [[ -z "$$simulator_id" ]]; then \
		simulator_id="$$(xcrun simctl list devices available | awk -F '[()]' '/^[[:space:]]+iPhone/ { print $$2; exit }')"; \
	fi; \
	test -n "$$simulator_id" || { echo "No available iPhone simulator found." >&2; exit 1; }; \
	xcrun simctl boot "$$simulator_id" 2>/dev/null || true; \
	open -a Simulator; \
	xcrun simctl bootstatus "$$simulator_id" -b; \
	echo "iPhone simulator $$simulator_id is ready."

simulator: ios-simulator ## Alias for ios-simulator.

relay-dev: ## Run the Cloudflare relay locally with Wrangler.
	cd "$(RELAY_DIR)" && $(NPM) run dev

relay-dev-https: ## Run the local relay over HTTPS for end-to-end web sessions.
	cd "$(RELAY_DIR)" && $(NPM) run dev -- --local-protocol=https

relay-deploy: ## Deploy the relay after setting CONFIRM_DEPLOY=1.
	@test "$(CONFIRM_DEPLOY)" = "1" || { echo "Set CONFIRM_DEPLOY=1 after reviewing relay/wrangler.toml." >&2; exit 2; }
	cd "$(RELAY_DIR)" && $(NPM) run deploy

check-app: generate format-check nearby-client-check drift-worker-check analyze test-flutter test-browser ## Run all non-native app checks.

check-relay: relay-check ## Run all relay checks.

check: check-app check-relay ## Run normal local checks across the repository.

ci: setup check build-web ## Reproduce the cross-platform CI checks locally.

ci-native: app-deps generate test-native build-macos-release verify-macos-release ## Reproduce native Apple CI checks.

clean: ## Remove Flutter build products and ephemeral platform metadata.
	cd "$(APP_DIR)" && $(FLUTTER) clean

clean-codegen: ## Remove build_runner's generated build cache.
	cd "$(APP_DIR)" && $(DART) run build_runner clean
