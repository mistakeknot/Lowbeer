# Brainstorm: Automated Test Suite (Models + Throttle Engine)

**Bead:** Lowbeer-p5i
**Date:** 2026-03-11

## Problem

Lowbeer has zero automated tests. All validation is manual — spawn a CPU-heavy process, observe the menu bar, check throttle behavior. This is fragile, slow, and doesn't catch regressions in:

- Rule evaluation logic (precedence, schedule matching, foreground skip)
- CPU % calculation (delta math, edge cases)
- Ring buffer correctness (wrap-around, ordering)
- Settings persistence (JSON round-trip, UserDefaults encoding)
- PID reuse safety (startTime verification)
- Safety list protection (names, paths, special PIDs)

## Current State

- **No test target** in Xcode project
- **No test files** anywhere in the repo
- Build system: Xcode project generated via `xcodeproj` Ruby gem
- Architecture: Mix of pure logic and system-coupled code (libproc, SIGSTOP, NSWorkspace)

## What's Testable Without Mocking

These are pure logic — no system dependencies:

1. **ProcessHistory** — ring buffer: append, wrap, samples ordering, peak/average/latest
2. **AppIdentity.matches()** — bundle ID vs path suffix matching
3. **ThrottleRule Codable** — JSON encode/decode round-trip
4. **ThrottleAction Codable** — encode/decode .stop, .throttleTo(x), .notifyOnly
5. **ThrottleSchedule + TimeOfDay + DayOfWeek** — Codable round-trip, comparisons
6. **ScheduleEvaluator.isActive()** — time window matching (normal, wrapping, inverted)
7. **SafetyList.isProtected()** — name/path/PID checks (static, no system calls)

## What Needs Protocol Abstraction for Testing

These touch system APIs that can't run in test harnesses:

1. **ProcessSampler** — `proc_listallpids`, `proc_pidinfo`, `sysctl` → protocol `ProcessSampling`
2. **ThrottleSession signal dispatch** — `kill(pid, SIGSTOP/SIGCONT)` → protocol `SignalSender`
3. **ForegroundObserver** — `NSWorkspace.shared` → protocol `ForegroundProviding`
4. **NotificationManager** — `UNUserNotificationCenter` → protocol `NotificationProviding`
5. **LowbeerSettings persistence** — `UserDefaults`, file I/O → test with temp directories

## Architecture: Testability Layer

```
Production code          Test code
─────────────           ──────────
ProcessSampler ←──── MockSampler (returns canned snapshots)
  (libproc)
SignalSender   ←──── MockSignalSender (records calls)
  (kill())
ForegroundProvider ← MockForeground (controllable PID)
  (NSWorkspace)
```

Key insight: **Don't refactor everything.** Add protocols only where tests need them. The pure logic (90% of test surface) needs no abstraction.

## Test Categories

### Tier 1: Pure Unit Tests (no system deps, fast)

| Component | Key Tests | Count |
|-----------|-----------|-------|
| ProcessHistory | append, wrap, samples order, peak/avg/latest, empty/single/full | ~8 |
| AppIdentity | bundle ID match, path match, nil bundle, empty path | ~6 |
| ThrottleRule | Codable round-trip, identity matching, enabled flag | ~4 |
| ThrottleAction | Codable for .stop, .throttleTo, .notifyOnly | ~4 |
| ScheduleEvaluator | normal range, wrapping midnight, day match, inverted, edge cases | ~8 |
| SafetyList | protected names, paths, PIDs, allowlist, own-process | ~6 |
| **Subtotal** | | **~36** |

### Tier 2: Logic Tests with Mocked Dependencies

| Component | Key Tests | Count |
|-----------|-----------|-------|
| RuleEvaluator | safety skip, rule match, no fallthrough, global fallback, schedule inactive, foreground skip, sustained duration | ~10 |
| ThrottleEngine.evaluate() | threshold → throttle, below threshold → resume, PID reuse detection, foreground auto-resume, ask-first flow, isPaused skips | ~12 |
| CPU % calculation | delta math, zero deltaTime, negative delta, sub-threshold filter | ~5 |
| **Subtotal** | | **~27** |

### Tier 3: Integration Tests (real processes, slower)

| Component | Key Tests | Count |
|-----------|-----------|-------|
| ProcessSampler.sampleAll() | returns non-empty, includes known PIDs, zombie filtering | ~3 |
| ThrottleSession (live) | SIGSTOP/SIGCONT on `yes > /dev/null` test process | ~2 |
| Settings persistence | JSON write/read with temp dir, UserDefaults encode/decode | ~4 |
| **Subtotal** | | **~9** |

**Total: ~72 tests**

## Test Target Setup

1. Add `LowbeerTests` target to Xcode project (via xcodeproj gem or manual)
2. Test files in `LowbeerTests/` directory
3. `@testable import Lowbeer` for internal access
4. No external test frameworks — use XCTest only (keep deps minimal)

## File Organization

```
LowbeerTests/
  Models/
    ProcessHistoryTests.swift
    AppIdentityTests.swift
    ThrottleRuleTests.swift
    ThrottleActionTests.swift
    ScheduleEvaluatorTests.swift
  Core/
    SafetyListTests.swift
    RuleEvaluatorTests.swift
    ThrottleEngineTests.swift
    ProcessMonitorTests.swift
  Integration/
    ProcessSamplerIntegrationTests.swift
    ThrottleSessionIntegrationTests.swift
    SettingsPersistenceTests.swift
  Mocks/
    MockProcessSampler.swift
    MockSignalSender.swift
    MockForegroundObserver.swift
```

## Protocol Extraction Plan

Minimal protocols needed (3 total):

```swift
protocol ProcessSampling {
    func sampleAll() -> [pid_t: ProcessSnapshot]
}

protocol SignalSending {
    func sendStop(pid: pid_t) -> Bool
    func sendCont(pid: pid_t) -> Bool
    func verifyProcess(pid: pid_t, expectedStartTime: timeval) -> Bool
}

protocol ForegroundProviding {
    var foregroundPID: pid_t { get }
    func isForeground(pid: pid_t) -> Bool
}
```

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| xcodeproj gem regeneration breaks test target | Add test target to gen script |
| @testable import requires same team/signing | Tests use Debug config only |
| ProcessSampler tests flaky on CI (no real processes) | Tier 3 tests marked with `@available` or skipped in CI |
| Protocol extraction changes production code | Minimal changes — add protocol conformance, inject via default params |

## Decision: Start with Tier 1

Ship Tier 1 (pure unit tests) first — ~36 tests, zero production code changes needed, immediate regression safety. Then layer in Tier 2 with protocol extraction. Tier 3 is nice-to-have for local development.

## Open Questions

1. Should we add the test target via xcodeproj Ruby script or manually edit project.pbxproj?
2. CI integration — is there a CI pipeline to add `xcodebuild test` to?
3. Code coverage target — 80%? Focus on critical paths only?
