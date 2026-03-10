# Apple Silicon Process Throttling: Research & Feasibility

> Research date: 2026-03-09
> Context: Lowbeer currently uses SIGSTOP/SIGCONT duty-cycling to throttle runaway processes.
> Goal: Explore smarter throttling alternatives on Apple Silicon (M1/M2/M3/M4).

---

## Table of Contents

1. [E-core / P-core Pinning](#1-e-core--p-core-pinning)
2. [macOS Process Throttling APIs](#2-macos-process-throttling-apis)
3. [Private / Undocumented APIs](#3-private--undocumented-apis)
4. [Battery & Energy Estimation](#4-battery--energy-estimation)
5. [Feasibility Matrix](#5-feasibility-matrix)
6. [Recommendations for Lowbeer](#6-recommendations-for-lowbeer)
7. [Sources](#7-sources)

---

## 1. E-core / P-core Pinning

### 1.1 QoS Classes and Core Affinity

On Apple Silicon, the kernel scheduler uses Quality of Service (QoS) classes to determine thread-to-core placement. This is the primary mechanism for E-core/P-core steering -- there is no direct "pin to E-core" API.

| QoS Class | Numeric Value | Core Placement |
|-----------|--------------|----------------|
| `QOS_CLASS_BACKGROUND` | 9 | **E-cores only** -- cannot be promoted to P-cores even when P-cores are idle |
| `QOS_CLASS_UTILITY` | 17 | Prefers E-cores, may overflow to P-cores under load |
| `QOS_CLASS_DEFAULT` | 21 | Mixed placement |
| `QOS_CLASS_USER_INITIATED` | 25 | Prefers P-cores, falls back to E-cores when P-cores are saturated |
| `QOS_CLASS_USER_INTERACTIVE` | 33 | Strongly prefers P-cores |

Key insight: `QOS_CLASS_BACKGROUND` (9) is the only QoS level that **guarantees** E-core-only execution. All higher QoS classes allow overflow between core types.

### 1.2 Setting QoS on Your Own Threads

These APIs work for self-modification only:

```swift
// pthread-level (C / bridged to Swift)
pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)

// GCD / Dispatch
DispatchQueue.global(qos: .background).async { /* work */ }

// posix_spawn (for child processes)
var attr = posix_spawnattr_t()
posix_spawnattr_init(&attr)
posix_spawnattr_set_qos_class_np(&attr, QOS_CLASS_BACKGROUND)
// Only QOS_CLASS_UTILITY and QOS_CLASS_BACKGROUND are valid here
```

### 1.3 Setting QoS on Another Process (the key question)

**This is the critical question for Lowbeer.** Can we demote an arbitrary same-user process to E-cores?

#### Option A: `taskpolicy -b -p <pid>` (works!)

The `taskpolicy` command-line tool can demote a running process to background QoS:

```bash
taskpolicy -b -p <pid>   # Demote to background (E-cores only)
taskpolicy -B -p <pid>   # Remove background demotion (restore P+E cores)
```

Under the hood, `taskpolicy` calls `setpriority(PRIO_DARWIN_BG)` and `setiopolicy_np()`. This:
- Sets scheduling priority to the lowest value
- Confines the process to E-cores on Apple Silicon
- Throttles disk I/O
- Throttles network I/O (for sockets opened after the change)

**Limitation:** Only works for **demotion** (confining to E-cores). Cannot promote a process that set itself to background QoS. On Apple Silicon, you cannot force a process onto P-cores.

#### Option B: `setpriority()` system call (limited)

```c
#include <sys/resource.h>
// PRIO_DARWIN_BG only supports who=0 (current process/thread)
setpriority(PRIO_DARWIN_BG, 0, 1);  // Set self to background
```

**Critical limitation:** `setpriority()` with `PRIO_DARWIN_BG` only supports `who == 0` (the calling process). You **cannot** use it to set background state on another process by PID. This is why `taskpolicy` wraps it differently -- it spawns a helper or uses a different internal path for the `-p` flag.

#### Option C: `nice` / `renice` (ineffective on Apple Silicon)

```bash
renice 20 -p <pid>   # Set lowest nice priority
```

On Apple Silicon, `nice`/`renice` are essentially **decorative**. They do not affect QoS-based scheduling or core placement. macOS's QoS system operates independently of Unix nice values. A process with nice 20 will still run on P-cores if its QoS class is high enough.

#### Option D: Mach `task_policy_set()` (requires task port)

```c
#include <mach/mach.h>
task_policy_set(task_port, TASK_OVERRIDE_QOS_POLICY, &policy_info, count);
```

To use this on another process, you need its Mach task port via `task_for_pid()`. This requires:
- **Root privileges**, OR
- The `com.apple.security.cs.debugger` entitlement, AND the target must have `com.apple.security.get-task-allow`
- Target must not be protected by SIP / hardened runtime

**Verdict:** Too restrictive for a user-facing app. Would require running as root or disabling SIP.

### 1.4 Practical Approach for Lowbeer

The most viable mechanism is to **shell out to `taskpolicy`** or replicate its behavior:

```swift
// Shell out approach
func demoteToECores(pid: pid_t) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
    process.arguments = ["-b", "-p", String(pid)]
    try? process.run()
    process.waitUntilExit()
}

func restoreFromECores(pid: pid_t) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
    process.arguments = ["-B", "-p", String(pid)]
    try? process.run()
    process.waitUntilExit()
}
```

The internal mechanism `taskpolicy -b -p` uses to modify another process likely involves the `process_policy` syscall (syscall 323) with `PROC_POLICY_ACTION_SET` and the `PROC_POLICY_DARWIN_BG` scope, which does accept an external PID. This is not a public API, but `taskpolicy` itself is a standard system utility.

---

## 2. macOS Process Throttling APIs

### 2.1 App Nap

App Nap is a system-managed feature (macOS 10.9+) that throttles backgrounded apps:
- Reduces CPU priority
- Throttles I/O
- Coalesces timers (fires less frequently)

**How it's controlled:**

```swift
// Prevent App Nap (from within the app being managed)
let activity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .idleSystemSleepDisabled],
    reason: "Performing critical work"
)
// ... later ...
ProcessInfo.processInfo.endActivity(activity)
```

**Limitation for Lowbeer:** App Nap is self-managed. An app opts in/out of App Nap itself. There is no public API to force another app into App Nap. macOS applies it automatically when an app's windows are not visible and it has no active power assertions.

**Relevance:** Low. Lowbeer targets processes that are actively consuming CPU regardless of visibility.

### 2.2 Thermal Pressure Notifications

```swift
// Public API -- available macOS 10.10.3+
NotificationCenter.default.addObserver(
    forName: ProcessInfo.thermalStateDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    let state = ProcessInfo.processInfo.thermalState
    switch state {
    case .nominal:  // All clear
    case .fair:     // Consider reducing non-essential work
    case .serious:  // Scale back significantly
    case .critical: // System is thermal throttling
    @unknown default: break
    }
}
```

**Relevance for Lowbeer:** High as a **trigger signal**. Lowbeer could become more aggressive about throttling when thermal state is `.serious` or `.critical`, and more lenient at `.nominal`. This is a public API, works without privileges, and is well-documented.

### 2.3 Process Resource Limits (`setrlimit`)

```c
struct rlimit rl;
rl.rlim_cur = cpu_seconds;
rl.rlim_max = cpu_seconds;
setrlimit(RLIMIT_CPU, &rl);
```

`RLIMIT_CPU` sets cumulative CPU time limits. When exceeded, the process receives `SIGXCPU` (soft limit) or `SIGKILL` (hard limit).

**Limitations:**
- Only works on the calling process (same limitation as `setpriority`)
- Measures cumulative CPU time, not CPU percentage
- Sends signals rather than throttling -- too blunt for Lowbeer's use case

### 2.4 `setiopolicy_np()` -- I/O Throttling

```c
#include <sys/resource.h>
setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_THROTTLE);
```

Controls I/O scheduling priority. Can throttle disk access for the calling process. Part of what `taskpolicy -b` enables. Not directly useful for CPU throttling but relevant for holistic resource management.

---

## 3. Private / Undocumented APIs

### 3.1 `proc_set_dirty` / `proc_get_dirty` / `proc_track_dirty`

```c
// Declared in <libproc.h> (semi-public)
int proc_track_dirty(pid_t pid, uint32_t flags);
int proc_set_dirty(pid_t pid, bool dirty);
int proc_get_dirty(pid_t pid, uint32_t *flags);
```

These APIs manage the "dirty" state of a process -- whether it has unsaved state. Used by the system for:
- Jetsam priority management (dirty processes are less likely to be killed)
- Memory pressure responses

**Relevance for Lowbeer:** Low. These control memory management behavior, not CPU scheduling. A "clean" process is more likely to be terminated under memory pressure, not throttled.

### 3.2 Coalition APIs

Coalitions are Darwin's mechanism for grouping related processes (e.g., an app and its XPC services):

```c
// XNU kernel structures (not directly accessible from userland)
coalition_t  // Opaque coalition handle
// Roles: Leader, XPC service, Extension
```

Coalitions have three roles:
- **Leader** -- the main app process
- **XPC service** -- helper processes
- **Extension** -- app extensions

The system uses coalitions for aggregate resource tracking and Jetsam decisions. A coalition's resource usage is the sum of all member processes.

**Relevance for Lowbeer:** Medium. Understanding coalitions could help Lowbeer throttle an app and all its helpers together, rather than just the main process. However, the coalition APIs are kernel-internal and not available from userland without private frameworks.

Reading coalition membership may be possible via `proc_pidinfo` with the right flavor, but setting coalition policies requires kernel privileges.

### 3.3 RunningBoard (`runningboardd`)

RunningBoard (macOS 10.15+) is the system daemon that manages process lifecycle:
- Tracks assertions about app state (foreground, background, suspended)
- Sets Jetsam priorities
- Can manage CPU, GPU, and memory limits
- Manages App Nap and process suspension

**Key behaviors:**
- For standard macOS apps: RunningBoard acts as a "commentator" -- it tracks state but doesn't actively manage resources
- For Catalyst (iPad) apps: RunningBoard actively manages lifecycle, including suspension and Jetsam

**Relevance for Lowbeer:** Low-to-none for direct use. RunningBoard is a system daemon with no public client API. However, understanding its behavior helps explain why some processes resist throttling (they hold RunningBoard assertions).

### 3.4 Energy Impact Calculation (Activity Monitor's Method)

Activity Monitor calculates "Energy Impact" using coefficients from plist files:

```
Path: /usr/share/pmenergy/<board-id>.plist
```

The formula multiplies system metrics by per-device coefficients:

```
Energy Impact = (kcpu_time * cpu_time)
              + (kcpu_wakeups * cpu_wakeups)
              + (kgpu_time * gpu_time)
              + (kdisk_io * disk_bytes)
              + (knetwork * network_packets)
```

Example coefficients: `kcpu_time = 1.0`, `kcpu_wakeups = 2.0e-4`.

The chain: Activity Monitor -> `libsysmon.dylib` -> `sysmond` -> `libpmenergy.dylib` -> IOKit/IOReport.

**Relevance for Lowbeer:** Medium-High. We could replicate this formula to show users estimated energy impact of throttled processes, though accessing `libpmenergy.dylib` is a private API.

### 3.5 IOReport (Private but Sudoless)

IOReport is the private framework that provides hardware-level power telemetry:

```c
// Private API -- used by powermetrics and macmon
CFDictionaryRef channels = IOReportCopyChannelsInGroup(
    CFSTR("Energy Model"), NULL, NULL, NULL, NULL);
// Subscribe, sample, compute deltas...
```

Key capabilities:
- CPU cluster power (per P-core cluster, per E-core cluster) in millijoules
- GPU power consumption
- ANE (Neural Engine) power
- DRAM power
- **No root required** (unlike `powermetrics`)

The open-source project [macmon](https://github.com/vladkens/macmon) demonstrates sudoless access to these metrics via IOReport.

**Relevance for Lowbeer:** High for energy estimation. Could show real-time power savings from throttling.

---

## 4. Battery & Energy Estimation

### 4.1 Battery State (Public API)

```swift
import IOKit.ps

func getBatteryInfo() -> (isCharging: Bool, percentage: Int, wattage: Double)? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
          let first = sources.first,
          let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
    else { return nil }

    let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
    let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
    let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
    let percentage = (capacity * 100) / maxCapacity

    // Instantaneous power draw (if available)
    let amperage = desc["InstantAmperage"] as? Int ?? 0
    let voltage = desc["Voltage"] as? Int ?? 0
    let wattage = Double(abs(amperage) * voltage) / 1_000_000.0

    return (isCharging, percentage, wattage)
}
```

Keys are defined in `<IOKit/ps/IOPSKeys.h>`. Available without root or entitlements.

### 4.2 System Power via IOReport (Private, No Root)

Using IOReport (as macmon does), Lowbeer could sample total system power:

```
CPU Power = P-core cluster power + E-core cluster power
GPU Power = GPU cluster power
Total SoC Power = CPU + GPU + ANE + DRAM
```

Sampling at intervals (e.g., every 3 seconds, matching Lowbeer's existing poll cycle) would allow computing:
- Power draw before/after throttling
- Estimated battery time saved

### 4.3 `powermetrics` (Root Required)

```bash
sudo powermetrics --samplers cpu_power -i 1000 -n 1
```

Provides the most detailed per-process energy data but requires root. Not practical for a menu bar app, but useful for development/validation.

Output includes:
- Per-process CPU time (ms/s)
- Per-process energy impact score
- Cluster-level power draw in milliwatts
- Frequency and residency per core

### 4.4 Practical Energy Estimation Strategy

For Lowbeer, a realistic approach would be:

1. **Before throttling:** Record CPU % of target process (already have this via `proc_pidinfo`)
2. **After throttling:** Record reduced CPU %
3. **Estimate savings:** Use a simplified model:
   ```
   CPU time saved (ms/s) = (old_cpu% - new_cpu%) * 10
   Estimated power saved (mW) ~= CPU_time_saved * coefficient
   ```
   The coefficient could be calibrated per chip using IOReport sampling, or use a conservative default (~10 mW per 1% CPU).

4. **Optional enhancement:** Use IOReport to sample actual SoC power before/after throttling to validate the model.

---

## 5. Feasibility Matrix

| Technique | Works on Another Process? | Requires Root? | Requires Entitlements? | Public API? | macOS Version | Effect on Apple Silicon |
|-----------|:------------------------:|:--------------:|:---------------------:|:-----------:|:-------------:|------------------------|
| **SIGSTOP/SIGCONT** (current) | Yes (same user) | No | No | Yes (POSIX) | All | Full stop/resume. No E-core awareness. |
| **`taskpolicy -b -p`** | Yes (same user) | No | No | Yes (CLI tool) | 10.9+ | Demotes to E-cores + throttles I/O |
| **`setpriority(PRIO_DARWIN_BG)`** | No (self only, who=0) | No | No | Yes | 10.x+ | Background QoS, E-cores only |
| **`pthread_set_qos_class_self_np`** | No (self only) | No | No | Yes | 10.10+ | Sets thread QoS, affects core placement |
| **`posix_spawnattr_set_qos_class_np`** | Child processes only | No | No | Yes | 10.10+ | QOS_CLASS_BACKGROUND or UTILITY only |
| **`nice` / `renice`** | Yes (same user, increase only) | No (to lower) | No | Yes (POSIX) | All | **Ineffective** on Apple Silicon -- does not affect QoS scheduling |
| **`task_policy_set` (Mach)** | Yes (with task port) | Yes* | `com.apple.security.cs.debugger` | Semi-public | All | Can override QoS |
| **`task_for_pid`** | N/A (access mechanism) | Yes* | Required | Semi-public | All | Blocked by SIP for protected processes |
| **App Nap** | No (self-managed) | No | No | Yes | 10.9+ | Timer coalescing, CPU/IO throttle |
| **Thermal state notifications** | N/A (read-only signal) | No | No | Yes | 10.10.3+ | Input signal for throttle decisions |
| **`proc_set_dirty`** | Yes (with pid) | Likely | No | Semi-public | 10.9+ | Memory management, not CPU |
| **Coalition APIs** | No (kernel-internal) | Yes | Yes | No | 10.10+ | Group resource tracking |
| **RunningBoard** | No (system daemon) | N/A | N/A | No | 10.15+ | Process lifecycle management |
| **IOReport (power sampling)** | N/A (read-only) | No | No | No (private) | 10.x+ | System-level power telemetry |
| **IOPSCopyPowerSourcesInfo** | N/A (battery info) | No | No | Yes | All | Battery state, charge %, wattage |
| **`powermetrics`** | N/A (read-only) | Yes (root) | No | Yes (CLI) | 10.9+ | Detailed per-process energy data |

\* Root or entitlements -- either one may suffice depending on target process protections.

---

## 6. Recommendations for Lowbeer

### Tier 1: Implement Now (Low Risk, High Value)

#### A. E-core demotion via `taskpolicy`

Add a "Slow Mode" that demotes processes to E-cores instead of fully stopping them:

```swift
enum ThrottleMode {
    case fullStop       // Current SIGSTOP/SIGCONT duty cycle
    case eCoreOnly      // taskpolicy -b (new)
    case dutyCycle(pct: Int)  // SIGSTOP/SIGCONT with on/off ratio (current)
}
```

**Advantages over SIGSTOP:**
- Process continues running (no UI freezes, no dropped connections)
- E-cores use ~1/3 the power of P-cores at similar utilization
- I/O is also throttled (disk + network)
- Can be combined with duty-cycling for even more control

**Implementation:** Shell out to `taskpolicy -b -p <pid>` / `taskpolicy -B -p <pid>`. No private APIs needed.

#### B. Thermal-aware throttling

Use `ProcessInfo.thermalState` to auto-adjust throttle aggressiveness:

```swift
// When thermal state is critical, auto-throttle anything above 50% CPU
// When nominal, only throttle above user-configured threshold
```

### Tier 2: Implement Next (Medium Effort, Good Value)

#### C. Hybrid throttle strategy

Combine E-core demotion with duty-cycling:

1. First, demote to E-cores (`taskpolicy -b`)
2. If CPU on E-cores still exceeds threshold, add SIGSTOP/SIGCONT duty-cycling
3. This provides a gentler degradation curve

#### D. Battery savings display

Use `IOPSCopyPowerSourcesInfo` (public API) to show:
- Current battery state
- Estimated time added by throttling (based on CPU reduction * coefficient)

### Tier 3: Future / Experimental

#### E. IOReport power telemetry

Use private IOReport APIs (as macmon does) for accurate power measurement:
- Show actual watts saved per throttled process
- Calibrate energy impact coefficients per chip model
- Risk: Private API may break between macOS versions

#### F. Coalition-aware throttling

When throttling a process, also throttle its XPC services and extensions. This requires discovering coalition membership, which may be possible via `proc_pidinfo` flavors.

### What NOT to Pursue

- **`task_for_pid` / Mach task ports:** Too many privilege requirements. Not viable for a distributed app.
- **`nice` / `renice`:** Ineffective on Apple Silicon. Misleading to users.
- **RunningBoard manipulation:** System daemon, no public interface, would break with updates.
- **`RLIMIT_CPU`:** Only works on self, sends kill signals rather than throttling.
- **`proc_set_dirty`:** Controls memory management, not CPU scheduling.

---

## 7. Sources

### Apple Developer Documentation
- [Energy Efficiency Guide: Prioritize Work at the Task Level](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html)
- [Energy Efficiency Guide: Respond to Thermal State Changes](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html)
- [Energy Efficiency Guide: App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
- [Tuning Your Code's Performance for Apple Silicon](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon)
- [Tune CPU Job Scheduling for Apple Silicon Games (WWDC Tech Talk)](https://developer.apple.com/videos/play/tech-talks/110147/)
- [ProcessInfo.thermalState](https://developer.apple.com/documentation/foundation/nsprocessinfo/1417480-thermalstate)
- [IOPSCopyPowerSourcesInfo](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo)
- [IOPMCopyBatteryInfo](https://developer.apple.com/documentation/iokit/1557138-iopmcopybatteryinfo)
- [setpriority(2) Man Page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setpriority.2.html)
- [Optimize for Apple Silicon with Performance and Efficiency Cores](https://developer.apple.com/news/?id=vk3m204o)

### The Eclectic Light Company (Howard Oakley)
- [How macOS Controls Performance: QoS on Intel and M1 Processors](https://eclecticlight.co/2022/01/07/how-macos-controls-performance-qos-on-intel-and-m1-processors/)
- [How You Can't Promote Threads on an M1](https://eclecticlight.co/2022/01/24/how-you-cant-promote-threads-on-an-m1/)
- [Making the Most of Apple Silicon Power: User Control](https://eclecticlight.co/2022/10/20/making-the-most-of-apple-silicon-power-5-user-control/)
- [How to Run Commands and Scripts on Efficiency Cores](https://eclecticlight.co/2021/09/14/how-to-run-commands-and-scripts-on-efficiency-cores/)
- [Apple Silicon: Cores, Clusters and Performance](https://eclecticlight.co/2024/02/19/apple-silicon-1-cores-clusters-and-performance/)
- [Tune for Performance: Core Types](https://eclecticlight.co/2024/12/17/tune-for-performance-core-types/)
- [How macOS Manages M1 CPU Cores](https://eclecticlight.co/2022/04/25/how-macos-manages-m1-cpu-cores/)
- [What is Quality of Service, and How Does It Matter?](https://eclecticlight.co/2025/05/09/what-is-quality-of-service-and-how-does-it-matter/)
- [RunningBoard: A New Subsystem in Catalina](https://eclecticlight.co/2019/11/07/runningboard-a-new-subsystem-in-catalina-to-detect-errors/)
- [Why E Cores Make Apple Silicon Fast](https://eclecticlight.co/2026/02/08/last-week-on-my-mac-why-e-cores-make-apple-silicon-fast/)

### Third-Party Tools & Research
- [App Tamer: Advanced Support for Apple Silicon Processors](https://www.stclairsoft.com/blog/2022/02/17/app-tamer-2-7b1-advanced-support-for-apple-silicon-processors/)
- [App Tamer: Running Apps on M1 Efficiency Cores](https://www.stclairsoft.com/blog/2022/01/21/app-tamer-experimentation-running-apps-on-m1-efficiency-cores/)
- [macmon: Sudoless Performance Monitoring for Apple Silicon](https://github.com/vladkens/macmon)
- [How to Get macOS Power Metrics with Rust (IOReport)](https://medium.com/@vladkens/how-to-get-macos-power-metrics-with-rust-d42b0ad53967)
- [What Does Activity Monitor's "Energy Impact" Actually Measure?](https://blog.mozilla.org/nnethercote/2015/08/26/what-does-the-os-x-activity-monitors-energy-impact-actually-measure/)
- [Power Measurement on macOS (Green Coding)](https://www.green-coding.io/blog/power-measurement-on-macos/)
- [AppPolice: MacOS App for Limiting CPU Usage](https://github.com/AppPolice/AppPolice)
- [Darwin's QoS Service Classes and Performance](https://jmmv.dev/2019/03/macos-threads-qos-and-bazel.html)
- [Building a macOS App to Know When My Mac Is Thermal Throttling](https://stanislas.blog/2025/12/macos-thermal-throttling-app/)

### Apple Open Source / XNU Kernel
- [XNU task_policy.c](https://github.com/apple/darwin-xnu/blob/main/osfmk/kern/task_policy.c)
- [XNU process_policy.c](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/process_policy.c)
- [XNU kern_memorystatus.c](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/kern_memorystatus.c)
- [taskpolicy(8) Man Page](https://ss64.com/mac/taskpolicy.html)

### Man Pages & System Reference
- [taskpolicy(8)](https://ss64.com/mac/taskpolicy.html)
- [powermetrics](https://ss64.com/mac/powermetrics.html)
- [Handling Low Memory Conditions in iOS and Mavericks](https://newosxbook.com/articles/MemoryPressure.html)
- [Who Needs task_for_pid Anyway?](https://newosxbook.com/articles/PST2.html)
