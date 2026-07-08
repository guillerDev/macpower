# Data Sources & Libraries

Every metric MacPower displays, and exactly which library/API/symbol produces it.
The design goal is **no elevated privileges** for everything except the optional
exact per-process energy mode.

## Metric → source map

| Metric | Library / API | Privilege | Implemented in |
|---|---|---|---|
| CPU / GPU / ANE / DRAM power | **IOReport** (private) | none | `Sampling/IOReportSampler.swift` |
| Per-core CPU power (E/P) | **IOReport** (private) | none | `Sampling/IOReportSampler.swift` |
| Per-core CPU utilisation | **Mach** `host_processor_info` | none | `Sampling/CPUUsageSampler.swift` |
| GPU utilisation / memory | **IOKit** `IOAccelerator` | none | `Sampling/GPUReader.swift` |
| Temperatures, fans, system & adapter power | **AppleSMC** (IOKit + SMC protocol) | none | `Sampling/SMCReader.swift`, `Sources/CSMC` |
| Thermal pressure state | **Foundation** `ProcessInfo.thermalState` | none | `Sampling/SMCReader.swift` |
| Battery health / specs / charge | **IOKit** `AppleSmartBattery` | none | `Sampling/BatteryReader.swift` |
| Per-process energy (approx.) | **libproc** `proc_pid_rusage` | none | `Sampling/ProcessSampler.swift` |
| Per-process energy (exact, optional) | **powermetrics** CLI | root | `Sampling/PowerMetricsService.swift` |

---

## 1. IOReport — SoC & per-core energy  *(private API)*

- **What:** Apple's private power-telemetry library — the same counters
  `powermetrics` reads internally.
- **Library:** `/usr/lib/libIOReport.dylib` (present only in the dyld shared
  cache; still linkable). Linked with `-lIOReport`.
- **Headers:** none ship in the SDK. Prototypes are re-declared in
  `Sources/CIOReport/include/CIOReport.h`, wrapped in `CF_IMPLICIT_BRIDGING_ENABLED`
  so Swift applies standard Create/Copy/Get memory rules.
- **Symbols used:** `IOReportCopyChannelsInGroup`, `IOReportCreateSubscription`,
  `IOReportCreateSamples`, `IOReportCreateSamplesDelta`, `IOReportIterate`,
  `IOReportChannelGetChannelName`, `IOReportChannelGetUnitLabel`,
  `IOReportChannelGetGroup`, `IOReportChannelGetSubGroup`,
  `IOReportChannelGetFormat`, `IOReportSimpleGetIntegerValue`,
  `IOReportStateGetCount` / `…GetNameForIndex` / `…GetResidency`.
- **Group read:** `"Energy Model"`. Relevant channels (Apple Silicon):
  - `CPU Energy` (mJ), `GPU Energy` (nJ), `ANE0` (mJ), `DRAM0` / `DCS0` (mJ)
  - Per-core: `EACC_CPU<n>` (efficiency), `PACC<c>_CPU<n>` (performance)
- **How:** subscribe once, then each tick take a sample, diff against the
  previous with `IOReportCreateSamplesDelta`, convert each channel's energy delta
  (normalised to nanojoules by unit label) to watts via `ΔnJ / seconds / 1e9`.
- **Notes:** private/undocumented → **not App Store eligible**, and Apple may
  change it between OS releases. Binned chips expose fused-off core slots that
  read zero forever; these are filtered by detecting zero cumulative energy at
  launch.

## 2. Mach host statistics — per-core CPU utilisation  *(public)*

- **API:** `host_processor_info(PROCESSOR_CPU_LOAD_INFO, …)` from `Darwin`/Mach.
- **Reads:** cumulative per-core ticks — `CPU_STATE_USER`, `_SYSTEM`, `_IDLE`,
  `_NICE`. Utilisation = busy-tick delta / total-tick delta between samples.
- **Memory:** the returned array is freed with `vm_deallocate`.

## 3. IOKit `IOAccelerator` — GPU stats  *(public)*

- **API:** `IOServiceGetMatchingService(IOServiceMatching("IOAccelerator"))` →
  `IORegistryEntryCreateCFProperties` → `"PerformanceStatistics"` dictionary.
- **Keys:** `Device Utilization %`, `Renderer Utilization %`, `Tiler Utilization %`,
  `In use system memory`, `Alloc system memory`.

## 4. AppleSMC — temperatures, fans, system/adapter power  *(protocol, no root)*

- **What:** the System Management Controller key protocol. Undocumented but
  stable; widely used (iStat Menus, Stats, smcFanControl).
- **Access:** `IOServiceOpen(AppleSMC)` + `IOConnectCallStructMethod` (selector
  `2`) with commands: read key-info (`9`), read bytes (`5`), read-by-index (`8`).
  Wrapped in the `CSMC` C target (`Sources/CSMC/smc.c`) so Swift never mirrors the
  fixed-layout SMC structs.
- **Keys used:**
  - `#KEY` — total key count (for discovery)
  - Temperatures (`flt`, °C), discovered by prefix: `Tp*` → CPU, `Tg*` → GPU,
    `TB*` → battery, `Ts*` → enclosure (averaged per group)
  - Fans: `FNum` (count), `F<n>Ac` (RPM), `F<n>Mn` / `F<n>Mx` (min/max)
  - `PSTR` — total system power (W)
  - `PDTR` — DC-in / wall-adapter input power (W)
- **Value decoding:** SMC data types `flt`, `fpe2`, `ui8`, `ui16`, `ui32`, `sp78`.
- **Notes:** the SMC exposes ~30 `P*` power rails, but they overlap (measurement
  points at different tree levels) and are unlabeled, so only the unambiguous
  totals (`PSTR`, `PDTR`) are used — the app does not fabricate a
  display/SSD/Wi-Fi breakdown.

## 5. Foundation `ProcessInfo` — thermal pressure  *(public)*

- **API:** `ProcessInfo.processInfo.thermalState` → `.nominal / .fair / .serious
  / .critical`. The only fully public, documented thermal signal.

## 6. IOKit `AppleSmartBattery` — battery details  *(public)*

- **API:** `IOServiceGetMatchingService(IOServiceMatching("AppleSmartBattery"))` →
  `IORegistryEntryCreateCFProperties`.
- **Keys:** `BatteryInstalled`, `DesignCapacity`, `AppleRawMaxCapacity`,
  `AppleRawCurrentCapacity`, `CurrentCapacity`, `MaxCapacity`, `CycleCount`,
  `Voltage` (mV), `Amperage` (mA, signed), `Temperature` (0.01 °C), `IsCharging`,
  `ExternalConnected`, `FullyCharged`, `AvgTimeToFull`, `AvgTimeToEmpty`,
  `BatteryHealthCondition`, `PermanentFailureStatus`, `Serial`.
- **Derived:** health = rawMax / design × 100; power = V × A (signed).

## 7. libproc — approximate per-process energy  *(public C)*

- **APIs (from `Darwin`):** `proc_listpids(PROC_ALL_PIDS)`,
  `proc_pid_rusage(pid, RUSAGE_INFO_V4, …)`, `proc_pidpath`, `proc_name`.
- **Fields:** `ri_user_time` + `ri_system_time` (CPU nanoseconds),
  `ri_pkg_idle_wkups` + `ri_interrupt_wkups` (wake-ups).
- **Model:** per-tick CPU-time delta → CPU %; energy impact ≈ CPU % +
  wake-ups/s × 0.02 (mirrors the signals Activity Monitor blends). This is an
  **estimate**, not measured energy.

## 8. powermetrics — exact per-process energy  *(CLI, root, optional)*

- **Command:** `/usr/bin/powermetrics --samplers tasks -f plist -i <ms>`, spawned
  via `sudo -n` as a streaming child `Process`.
- **Parsing:** output is a stream of plist documents separated by NUL bytes; each
  is parsed with `PropertyListSerialization`, reading `tasks[].pid` and
  `energy_impact_per_s` (falling back to `energy_impact`).
- **Privilege:** requires root. A one-time passwordless rule
  (`/etc/sudoers.d/macpower`, validated with `visudo -c`) is installed via a
  single native admin prompt (`osascript … with administrator privileges`).
  Without it, the service reports `.needsSetup` instead of prompting.

---

## Frameworks linked (see `Package.swift`)

| Target | Links |
|---|---|
| `CIOReport` (C shim) | `libIOReport`, `CoreFoundation` |
| `CSMC` (C shim) | `IOKit`, `CoreFoundation` |
| `MacPower` (app) | `IOKit`, `AppKit` (+ SwiftUI, Charts, Observation, Foundation via `import`) |

Non-metric frameworks: **SwiftUI** + **Swift Charts** (UI), **Observation**
(`@Observable`), **AppKit** (app activation policy, icon rendering).

## Privilege summary

- **No root:** IOReport, Mach host statistics, IOAccelerator, AppleSMC,
  AppleSmartBattery, libproc, ProcessInfo — i.e. **everything by default**.
- **Root (opt-in only):** powermetrics exact per-process energy.

## Appendix: CLI tools for manual inspection

MacPower reads most metrics through native APIs (not by shelling out), but the
following built-in command-line tools expose the **same underlying data** and are
useful for cross-checking what the app reports. Only `powermetrics` is used by the
app itself (exact per-process mode).

### Battery

```sh
# Rich battery + adapter + power-settings report (charge, health %, cycle count,
# condition, serial, model). Add -json / -xml for machine-readable output.
system_profiler SPPowerDataType

# Same registry node the app reads via IOKit — every raw AppleSmartBattery key
# (AppleRawMaxCapacity, CycleCount, Voltage, Amperage, BatteryHealthCondition …).
ioreg -rn AppleSmartBattery

# Quick charge %, power source, and charging state.
pmset -g batt

# Power-adapter details (wattage, family) when plugged in.
pmset -g adapter
```
→ App equivalent: `BatteryReader.swift` (IOKit `AppleSmartBattery`).

### GPU

```sh
# GPU PerformanceStatistics: "Device Utilization %", memory, etc.
ioreg -rc IOAccelerator -d 1
ioreg -rn AGXAccelerator -d 1          # Apple Silicon accelerator node

# GPU model / core count / metal support.
system_profiler SPDisplaysDataType
```
→ App equivalent: `GPUReader.swift` (IOKit `IOAccelerator`).

### CPU / SoC power & per-core

```sh
# CPU + GPU power, per-cluster/per-core residency & frequency (root).
sudo powermetrics --samplers cpu_power,gpu_power
sudo powermetrics --samplers cpu_power -f plist -i 1000     # plist stream

# CPU topology (E/P core counts, chip name) — how cores are grouped.
sysctl -a | grep -E 'machdep.cpu.brand_string|hw.perflevel|hw.ncpu'
```
→ App equivalent: `IOReportSampler.swift` (IOReport, no root) for power;
`CPUUsageSampler.swift` (`host_processor_info`) for per-core utilisation.
Note: the app gets SoC power from **IOReport without root**; `powermetrics` is the
root-required CLI that reads the same counters.

### Per-process energy

```sh
# Live per-process energy-impact ("POWER") column — the CLI analogue of the
# app's approximate mode.
top -stats pid,command,cpu,power -o power

# Exact per-process energy impact (root). This IS what the app's optional
# "Exact energy" toggle runs under the hood.
sudo powermetrics --samplers tasks --show-process-energy
sudo powermetrics --samplers tasks -f plist -i 1000        # plist stream
```
→ App equivalent: `ProcessSampler.swift` (libproc, approx, no root) /
`PowerMetricsService.swift` (powermetrics, exact, root).

### Temperatures, fans & total system power

```sh
# Thermal pressure / CPU power-throttling status.
pmset -g therm
sysctl machdep.xcpm.cpu_thermal_level      # numeric thermal level — INTEL ONLY
                                           # (absent on Apple Silicon)

# Thermal sampler (root). Note: raw SMC temperature/fan keys (Tp*, Tg*, F*,
# PSTR, PDTR) have no first-party CLI — the app reads them directly via the
# AppleSMC protocol; third-party tools (istats, smckit) expose them on the CLI.
sudo powermetrics --samplers thermal
```
→ App equivalent: `SMCReader.swift` + `Sources/CSMC` (AppleSMC) for temps/fans/
`PSTR`/`PDTR`; `ProcessInfo.thermalState` for the pressure level.

### powermetrics sampler reference

`powermetrics` (always root) is the closest single CLI to the whole app. Useful
samplers: `cpu_power`, `gpu_power`, `ane_power`, `tasks`, `battery`, `thermal`,
`smc` (Intel only), `network`, `disk`. Common flags:

```sh
sudo powermetrics --samplers cpu_power,gpu_power,tasks,battery \
     --format plist --sample-count 1 --sample-rate 1000
```

## App Store note

Because IOReport is a **private** API, MacPower is intended for **direct
distribution** (notarized `.app`), not the Mac App Store, which forbids private
API usage.
