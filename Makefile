.PHONY: build test bundle icon run clean

# Compile (debug).
build:
	swift build

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
