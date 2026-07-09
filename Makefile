.PHONY: build test bundle icon run clean format lint deadcode hooks

# Compile (debug).
build:
	swift build

# Auto-format all sources in place (Apple swift-format, bundled with the toolchain).
format:
	swift format --configuration .swift-format --in-place --recursive Sources Tests

# Lint: formatting (swift-format) + semantic rules (SwiftLint). Non-zero on issues.
lint:
	swift format lint --configuration .swift-format --strict --recursive Sources Tests
	swiftlint lint --quiet --strict

# Dead-code audit (periphery). Run manually; not a CI gate (needs a full build).
deadcode:
	periphery scan --quiet

# Install the git pre-commit hook (format + lint on staged files).
hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/*
	@echo "Installed .githooks (pre-commit format + lint gate)."

# Pure-logic unit tests (no SMC/IOReport hardware required).
test:
	swift test

# Generate the icon (best-effort) and assemble dist/MacPower.app (release).
bundle:
	./Scripts/make_icon.sh || echo "icon generation skipped"
	./Scripts/bundle.sh release

# Regenerate the app icon only.
icon:
	./Scripts/make_icon.sh

# Build and launch the app.
run:
	swift run

clean:
	swift package clean
	rm -rf dist Icon
