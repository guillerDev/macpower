# AGENTS.md — MacPower

Native macOS SwiftUI app that visualises real-time system power consumption
(SoC / CPU / GPU / ANE / DRAM, per-process energy, battery, thermal) with **no
root required**. Data comes from the private **IOReport** API, IOKit, and the SMC
key protocol — see [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md) for the full
per-metric source map.

Because IOReport is a private Apple API, the app is **not** Mac App Store
eligible — it ships as a direct-distribution, ad-hoc-signed `.app`.

## Toolchain

- Swift Package Manager, no external dependencies. macOS 14+ (Sonoma).
- `swift-tools-version: 6.0` (Xcode 16+), but the app/test targets build in
  **Swift 5 language mode** (`.swiftLanguageMode(.v5)`).
- Targets: `CIOReport` and `CSMC` (thin C shims for IOReport and the SMC
  protocol), `MacPower` (the SwiftUI executable), `MacPowerTests`.

## Build & run

```sh
make run      # swift run — build and launch
make build    # swift build (debug)
make test     # swift test — pure-logic unit tests (no hardware needed)
make bundle   # assemble dist/MacPower.app (release) — icon + ad-hoc sign
```

## Layout

```
Sources/
  CIOReport/  CSMC/            # C interop shims (system frameworks)
  MacPower/
    Sampling/                  # IOReport / SMC / GPU / battery / process readers
    Models/                    # PowerMonitor, SamplingEngine, snapshots
    Support/                   # formatters, small extensions
    Views/                     # SwiftUI views (menu bar + windows)
Tests/MacPowerTests/           # channel classification, unit conversion, formatting
```

## Code quality

General tooling workflow (swift-format vs SwiftLint separation, fixing failures,
hooks) is documented in the portable **`code-quality`** skill. This repo's
concrete setup:

- **`make lint`** is the CI gate — `swift format lint --strict --recursive
  Sources Tests` + `swiftlint lint --quiet --strict`. Run `make format` first;
  most lint failures are just formatting.
- **`.swift-format`**: 110-column line length, 4-space indent, ordered imports,
  max 1 blank line.
- **`.swiftlint.yml`**: short identifiers allowed (`i n w e g t`); formatting-
  overlap rules disabled (`line_length`, `opening_brace`, `trailing_comma`) plus
  two false-positive rules (`implicit_optional_initialization`,
  `optional_data_string_conversion`). Body/type-length and complexity thresholds
  are relaxed for the SwiftUI views and the IOReport decoder — tighten them as
  those files shrink; don't raise them for the next file.
- **No `.periphery.yml`** — `make deadcode` runs `periphery scan --quiet`
  config-less over the SPM package. It's a manual audit, not a CI gate.
- **Git hooks** live in `.githooks/` (pre-commit: format + lint on staged Swift;
  pre-push: periphery). Enable once per clone with `make hooks`
  (`core.hooksPath` is local git config, not committed).

CI: [.github/workflows/ci.yml](.github/workflows/ci.yml) runs `make lint`,
`make test`, `make build`, then `make bundle` and verifies the bundle.

## Release

Releases are tag-driven — pushing `vX.Y.Z` builds the app, publishes a GitHub
Release, and bumps the Homebrew cask. See the **`release`** skill and
[docs/RELEASING.md](docs/RELEASING.md). Licensed under [MIT](LICENSE).
