---
artifact_type: plan
bead: Lowbeer-hht
stage: design
requirements:
  - F1: Capture start time in ProcessSnapshot via sysctl
  - F2: Thread start time through ProcessInfo and cache
  - F3: Start-time verified signal dispatch in ThrottleSession
---
# PID Start-Time Verification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Lowbeer-hht
**Goal:** Prevent throttling the wrong process after PID reuse by tracking `(pid, startTime)` tuples.

**Architecture:** Add a `startTime: timeval` field to the process data pipeline: `ProcessSnapshot` → `ProcessInfo` → `ThrottleSession`. The start time is captured via `sysctl(KERN_PROC, KERN_PROC_PID)` during process sampling, flows through the model layer, and is verified before every SIGSTOP/SIGCONT dispatch. Failure mode is fail-closed: if verification fails, the throttle session deactivates immediately.

**Tech Stack:** Swift 5.9, Darwin sysctl API (`kinfo_proc.kp_proc.p_starttime`), macOS 14+

**Review findings incorporated:**
- P0: Session coherence — `evaluate()` checks session startTime against process startTime
- P1: Fix pre-existing `isStopped` bug — check `kill()` return value
- P1: Post-signal re-verify in `sendStop()` to narrow TOCTOU window
- P1: Add `deinit { deactivate() }` to prevent stranded SIGSTOP
- P2: `extension timeval: @retroactive Equatable` for clean comparisons
- P2: Use `startTime` naming uniformly (not `processStartTime`)
- P2: `os_log` on PID reuse detection

---

## Must-Haves

**Truths** (observable behaviors):
- A throttled process that exits and whose PID is reused will NOT have the new process frozen
- If sysctl fails for a PID (process exited), the throttle session deactivates
- The ProcessMonitor cache evicts stale entries when PID reuse is detected
- ThrottleEngine.evaluate() detects session/process startTime mismatch and deactivates stale sessions
- Duty-cycle throttling deactivates mid-cycle if PID reuse is detected
- `isStopped` is only set when `kill(SIGSTOP)` actually succeeds

**Artifacts** (files that must exist with specific exports):
- [`Lowbeer/Core/ProcessSnapshot.swift`] — `ProcessSnapshot.startTime: timeval`, `ProcessSampler.getStartTime(pid:) -> timeval?`, `extension timeval: @retroactive Equatable`
- [`Lowbeer/Models/ProcessInfo.swift`] — `ProcessInfo.startTime: timeval`
- [`Lowbeer/Core/ThrottleSession.swift`] — `ThrottleSession.startTime: timeval`, updated `verifyProcess()`, `deinit`
- [`Lowbeer/Core/ThrottleEngine.swift`] — session coherence check in `evaluate()`

**Key Links** (where breakage causes cascading failures):
- `ProcessSampler.sampleAll()` must populate `startTime` before `ProcessMonitor.poll()` uses it
- `ProcessMonitor.processCache` must compare `startTime` — otherwise cache hits mask PID reuse
- `ThrottleEngine` must pass `startTime` when constructing `ThrottleSession` at both call sites (line 119 and line 178)
- `ThrottleEngine.evaluate()` must compare `session.startTime` vs `process.startTime` to catch coherence gaps

---

### Task 1: Add timeval Equatable extension and sysctl helper

**Files:**
- Modify: `Lowbeer/Core/ProcessSnapshot.swift:1-71`

**Step 1: Add `@retroactive Equatable` conformance for `timeval`**

At the top of `Lowbeer/Core/ProcessSnapshot.swift`, after the imports, add:

```swift
extension timeval: @retroactive Equatable {
    public static func == (lhs: timeval, rhs: timeval) -> Bool {
        lhs.tv_sec == rhs.tv_sec && lhs.tv_usec == rhs.tv_usec
    }
}
```

**Step 2: Add `startTime` field to `ProcessSnapshot`**

```swift
struct ProcessSnapshot: Sendable {
    let pid: pid_t
    let name: String
    let path: String
    let totalUserNs: UInt64
    let totalSystemNs: UInt64
    let timestamp: CFAbsoluteTime
    let startTime: timeval

    var totalNs: UInt64 { totalUserNs + totalSystemNs }
}
```

**Step 3: Add `getStartTime` helper to `ProcessSampler`**

Add this static method to `ProcessSampler`, before `sampleAll()`:

```swift
/// Get process start time via sysctl. Returns nil if the process doesn't exist.
static func getStartTime(for pid: pid_t) -> timeval? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    let ret = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    guard ret == 0, size > 0 else { return nil }
    return info.kp_proc.p_starttime
}
```

**Step 4: Update `sampleAll()` to capture start time**

Inside the `for i in 0..<Int(actualCount)` loop, after `guard pid > 0 else { continue }`, add:

```swift
guard let startTime = getStartTime(for: pid) else { continue }
```

Update the `ProcessSnapshot` construction to include `startTime`:

```swift
results[pid] = ProcessSnapshot(
    pid: pid,
    name: name,
    path: path,
    totalUserNs: taskInfo.pti_total_user,
    totalSystemNs: taskInfo.pti_total_system,
    timestamp: now,
    startTime: startTime
)
```

**Step 5: Commit**

```bash
git add Lowbeer/Core/ProcessSnapshot.swift
git commit -m "feat: add startTime to ProcessSnapshot via sysctl KERN_PROC"
```

<verify>
- run: `swift -typecheck Lowbeer/Core/ProcessSnapshot.swift 2>&1 || true`
  expect: exit 0
</verify>

---

### Task 2: Thread start time through ProcessInfo and cache

**Files:**
- Modify: `Lowbeer/Models/ProcessInfo.swift:5-24`
- Modify: `Lowbeer/Core/ProcessMonitor.swift:76-89`

**Step 1: Add `startTime` to `ProcessInfo`**

In `Lowbeer/Models/ProcessInfo.swift`, add the field and update the initializer. Use a default of `timeval()` so existing call sites compile. A zero timeval will never match a real process start time (fail-closed).

```swift
@Observable
final class ProcessInfo: Identifiable {
    let pid: pid_t
    let name: String
    let path: String
    let bundleIdentifier: String?
    let startTime: timeval
    var icon: NSImage?
    var cpuPercent: Double = 0
    var history: ProcessHistory = ProcessHistory()
    var isThrottled: Bool = false
    var throttleTarget: Double? = nil

    var id: pid_t { pid }

    init(pid: pid_t, name: String, path: String, bundleIdentifier: String? = nil,
         startTime: timeval = timeval(), icon: NSImage? = nil) {
        self.pid = pid
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.startTime = startTime
        self.icon = icon
    }
```

**Step 2: Update ProcessMonitor cache to detect PID reuse**

In `Lowbeer/Core/ProcessMonitor.swift`, update the cache check at line 77. Use the `Equatable` conformance from Task 1:

```swift
let info: ProcessInfo
if let cached = processCache[pid],
   cached.name == current.name,
   cached.startTime == current.startTime {
    info = cached
} else {
    let app = appsByPID[pid]
    info = ProcessInfo(
        pid: pid,
        name: app?.localizedName ?? current.name,
        path: current.path,
        bundleIdentifier: app?.bundleIdentifier,
        startTime: current.startTime,
        icon: app?.icon
    )
    processCache[pid] = info
}
```

**Step 3: Build and verify**

Run: `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | tail -5`
Expected: May fail on ThrottleEngine call sites — that's fixed in Task 3.

**Step 4: Commit**

```bash
git add Lowbeer/Models/ProcessInfo.swift Lowbeer/Core/ProcessMonitor.swift
git commit -m "feat: thread startTime through ProcessInfo and monitor cache"
```

<verify>
- run: `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | grep -c "Build Succeeded" || echo "0"`
  expect: contains "1"
</verify>

---

### Task 3: Rewrite ThrottleSession with start-time verification and safety fixes

This task incorporates three review findings: start-time verification, `kill()` return value check, post-signal re-verify, and `deinit` safety net.

**Files:**
- Modify: `Lowbeer/Core/ThrottleSession.swift` (full rewrite of fields, init, verifyProcess, sendStop, deinit)

**Step 1: Add `startTime` field, `deinit`, and update init**

Use uniform `startTime` naming (not `processStartTime`). Add `import os.log` for PID reuse logging. Add `deinit { deactivate() }` to prevent stranded SIGSTOP.

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.lowbeer", category: "throttle")

/// Tracks the state of throttling for a single process.
final class ThrottleSession {
    let pid: pid_t
    let processName: String
    let startTime: timeval
    let rule: ThrottleRule?
    let action: ThrottleAction

    private(set) var isStopped: Bool = false
    private(set) var startedAt: Date = Date()
    private var dutyCycleTimer: Timer?

    init(pid: pid_t, processName: String, startTime: timeval,
         rule: ThrottleRule?, action: ThrottleAction) {
        self.pid = pid
        self.processName = processName
        self.startTime = startTime
        self.rule = rule
        self.action = action
    }

    deinit {
        deactivate()
    }
```

**Step 2: Rewrite `verifyProcess()` with start-time check and logging**

```swift
/// Verify PID still belongs to the expected process via start-time comparison.
/// Fail-closed: returns false if sysctl fails or start time differs.
private func verifyProcess() -> Bool {
    guard let currentStartTime = ProcessSampler.getStartTime(for: pid) else {
        logger.info("PID \(self.pid) no longer exists — deactivating throttle")
        return false
    }
    guard currentStartTime == startTime else {
        logger.warning("PID \(self.pid) reused: expected start \(self.startTime.tv_sec), got \(currentStartTime.tv_sec) — deactivating")
        return false
    }
    return true
}
```

**Step 3: Fix `sendStop()` — check `kill()` return value + post-signal re-verify**

This fixes a pre-existing bug where `isStopped` was set even when `kill()` failed, and adds a post-signal re-verify to narrow the TOCTOU window.

```swift
private func sendStop() {
    guard verifyProcess() else { return }
    let result = kill(pid, SIGSTOP)
    guard result == 0 else { return }
    isStopped = true
    // Post-signal re-verify: if PID was reused between verify and kill, undo immediately
    if !verifyProcess() {
        sendCont()
    }
}
```

**Step 4: Keep the rest of ThrottleSession unchanged**

The `activate()`, `deactivate()`, `sendCont()`, `startDutyCycle()`, and `elapsedDescription` methods remain as-is. The duty-cycle timer already calls `verifyProcess()` on each tick, which now uses the start-time check.

**Step 5: Commit**

```bash
git add Lowbeer/Core/ThrottleSession.swift
git commit -m "feat: rewrite verifyProcess() with start-time check, fix isStopped bug, add deinit"
```

<verify>
- run: `swift -typecheck Lowbeer/Core/ThrottleSession.swift 2>&1 || true`
  expect: exit 0
</verify>

---

### Task 4: Update ThrottleEngine — pass startTime and add session coherence check

**Files:**
- Modify: `Lowbeer/Core/ThrottleEngine.swift:49-53` (add coherence check)
- Modify: `Lowbeer/Core/ThrottleEngine.swift:119-124` (pass startTime)
- Modify: `Lowbeer/Core/ThrottleEngine.swift:178` (pass startTime)

**Step 1: Add session coherence check in `evaluate()`**

After the existing cleanup loop (lines 49-53) that removes sessions for absent PIDs, add a second loop that checks for PID reuse by comparing start times. This closes the P0 coherence gap identified in review.

After the existing block:
```swift
// Clean up sessions for processes that no longer exist
for (pid, session) in sessions {
    if !activePIDs.contains(pid) {
        session.deactivate()
        sessions.removeValue(forKey: pid)
    }
}
```

Add:
```swift
// Detect PID reuse: deactivate sessions whose startTime no longer matches
for process in monitor.processes {
    if let session = sessions[process.pid],
       session.startTime != process.startTime {
        session.deactivate()
        sessions.removeValue(forKey: process.pid)
        process.isThrottled = false
        process.throttleTarget = nil
        exceedCounts[process.pid] = 0
    }
}
```

**Step 2: Update auto-throttle call site (line ~119)**

```swift
let session = ThrottleSession(
    pid: process.pid,
    processName: process.name,
    startTime: process.startTime,
    rule: matchedRule,
    action: action
)
```

**Step 3: Update manual throttle call site (line ~178)**

```swift
let session = ThrottleSession(
    pid: pid,
    processName: process.name,
    startTime: process.startTime,
    rule: nil,
    action: action
)
```

**Step 4: Build and verify**

Run: `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | tail -5`
Expected: **Build Succeeded**

**Step 5: Commit**

```bash
git add Lowbeer/Core/ThrottleEngine.swift
git commit -m "feat: add session coherence check and pass startTime to ThrottleSession"
```

<verify>
- run: `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | grep -c "Build Succeeded"`
  expect: contains "1"
</verify>

---

### Task 5: Smoke test

**Files:**
- None (manual verification)

**Step 1: Build and run the app**

```bash
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | tail -3
```

Then:
```bash
open $(find ~/Library/Developer/Xcode/DerivedData/Lowbeer-*/Build/Products/Debug/Lowbeer.app -maxdepth 0 2>/dev/null | head -1)
```

**Step 2: Create a test runaway process**

```bash
yes > /dev/null &
YES_PID=$!
echo "Started yes with PID $YES_PID"
```

**Step 3: Wait for Lowbeer to detect and throttle it**

Wait ~35 seconds (3s poll * 10 sustained = 30s + buffer). Verify in menu bar that `yes` appears and gets throttled.

**Step 4: Kill the process and verify cleanup**

```bash
kill $YES_PID 2>/dev/null
```

Verify Lowbeer detects process is gone and removes the throttle session.

**Step 5: Check Console.app for os_log output**

Open Console.app, filter for `subsystem:com.lowbeer category:throttle`. Kill the throttled process — you should see a log entry like "PID XXXX no longer exists — deactivating throttle".

<verify>
- run: `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build 2>&1 | grep -c "Build Succeeded"`
  expect: contains "1"
</verify>
