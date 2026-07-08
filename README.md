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

Because IOReport is a private (undocumented) Apple API, this app is **not** Mac App Store eligible — it is meant for direct distribution (notarized `.app`).

## Build & run

```bash
swift run                 # build and launch
./Scripts/bundle.sh       # produce a double-clickable dist/MacPower.app
open dist/MacPower.app
```

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+). Tested on Apple Silicon (M1 Pro).
