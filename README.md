# MacPower

A native macOS app that visualises real-time system power consumption — **no root required**.

## Sections

- **Overview** — total SoC power with a Sankey diagram (System → CPU / GPU / ANE / DRAM, and CPU → E-cores / P-cores), plus a stacked power-over-time chart.
- **CPU** — per-core utilisation and power, grouped into efficiency and performance clusters.
- **GPU** — utilisation (device / renderer / tiler), power, and memory usage.
- **Processes** — a sortable table of processes ranked by energy impact (approximate by default; **optional exact mode** via powermetrics).
- **Battery** — charge, health, cycle count, condition, capacity specs, and live power flow.
- **Thermal** — thermal-pressure state, CPU/GPU/battery/enclosure temperatures, fan RPM, and total system power (SMC `PSTR`).

Also includes a **menu-bar item** showing live SoC wattage with a popover breakdown.

## How it gets the data (no privileges needed)

| Metric | Source |
|---|---|
| CPU / GPU / ANE / DRAM power, per-core power | Private **IOReport** API (`libIOReport.dylib`) — the same counters `powermetrics` reads |
| Per-core CPU utilisation | `host_processor_info` |
| GPU utilisation / memory | IOKit `IOAccelerator` PerformanceStatistics |
| Temperatures, fans, total system power | SMC key protocol (`AppleSMC`) |
| Thermal pressure | `ProcessInfo.thermalState` (public API) |
| Battery health / specs / charge | IOKit `AppleSmartBattery` |
| Per-process energy (default) | **Approximated** from `libproc` CPU-time + idle-wakeup deltas |
| Per-process energy (exact, optional) | `powermetrics` tasks sampler — requires root |

> Per-process energy is an estimate by default so the app runs instantly with no password. The **Processes → Exact energy** toggle switches to `powermetrics` for precise figures; the first time, it installs a one-time passwordless-sudo rule (`/etc/sudoers.d/macpower`) via a single native admin prompt.

**Full details** — every library, API symbol, and SMC/IOKit key used per metric is documented in [`docs/DATA-SOURCES.md`](docs/DATA-SOURCES.md).

Because IOReport is a private (undocumented) Apple API, this app is **not** Mac App Store eligible — it is meant for direct distribution (notarized `.app`).

## Build & run

```bash
make run        # build and launch (swift run)
make test       # run the pure-logic unit tests
make build      # compile only (debug)
make bundle     # produce a double-clickable dist/MacPower.app (release)
open dist/MacPower.app
```

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+). Tested on Apple Silicon (M1 Pro).

## Releasing

Releases are automated by the [`Release`](.github/workflows/release.yml) GitHub
Actions workflow: it builds the app, publishes a GitHub Release with a zipped
`MacPower.app`, and (optionally) bumps the Homebrew cask.

**Cut a release** by pushing a version tag:

```bash
git tag v1.0.0
git push --tags
```

The workflow then builds `dist/MacPower.app`, zips it as `MacPower-v1.0.0.zip`,
computes its `sha256`, and creates the GitHub Release with install instructions.
You can also trigger it manually from the **Actions** tab (workflow_dispatch).

**Homebrew (optional).** Distribute via a personal tap:

```bash
brew install --cask <owner>/tap/macpower
```

One-time setup — create a `homebrew-tap` repo, copy
[`packaging/homebrew/macpower.rb`](packaging/homebrew/macpower.rb) to its
`Casks/` folder (replacing `OWNER`), and optionally add a `TAP_GITHUB_TOKEN`
secret so the workflow auto-bumps the cask on each release.

> The app is **ad-hoc signed, not notarized**, so downloaded copies are
> Gatekeeper-quarantined; users clear it with
> `xattr -dr com.apple.quarantine MacPower.app`. For a frictionless install, add a
> Developer-ID sign + notarize step before packaging.

Full details, including CI, are in [`docs/RELEASING.md`](docs/RELEASING.md).

## Continuous integration

The [`CI`](.github/workflows/ci.yml) workflow runs on every push/PR: it runs the
tests, compiles the app, assembles the `.app` bundle, and verifies it.
