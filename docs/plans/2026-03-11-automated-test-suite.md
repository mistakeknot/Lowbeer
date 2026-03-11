# Plan: Automated Test Suite (Models + Throttle Engine)

**Bead:** Lowbeer-p5i
**Date:** 2026-03-11

## Overview

Add XCTest target and implement ~65 unit tests covering all models, evaluators, and the throttle engine. Minimal production code changes — only protocol extraction where mock injection is needed.

## Step 1: Create Test Infrastructure

### 1a: Create LowbeerTests directory and test files

```
LowbeerTests/
  Models/
    ProcessHistoryTests.swift
    AppIdentityTests.swift
    ThrottleRuleCodableTests.swift
    ScheduleEvaluatorTests.swift
  Core/
    SafetyListTests.swift
    RuleEvaluatorTests.swift
    ThrottleEngineTests.swift
  Mocks/
    MockForegroundObserver.swift
```

### 1b: Update Xcode project to include test target

Regenerate `Lowbeer.xcodeproj` with test target, or manually add the `LowbeerTests` target. The test target must:
- Link against the `Lowbeer` app target
- Use `@testable import Lowbeer`
- Deployment target: macOS 14.0
- Scheme: `LowbeerTests` or integrated into `Lowbeer` scheme

### 1c: Verify build

```bash
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build-for-testing
```

## Step 2: Pure Model Tests (Tier 1)

### 2a: ProcessHistoryTests.swift (~8 tests)

Tests for the ring buffer:
- `testAppendSingle` — append one value, verify latest/count/samples
- `testAppendFillCapacity` — fill to capacity, verify all samples present in order
- `testAppendWrapAround` — exceed capacity, verify oldest dropped, ordering correct
- `testSamplesChronological` — after wrap, samples returns oldest→newest
- `testLatestReturnsLastAppended` — after multiple appends
- `testPeakReturnsMax` — peak among all buffered values
- `testAverageCalculation` — average of known values
- `testEmptyDefaults` — latest=0, peak=0, average=0, count=0, samples=[]

### 2b: AppIdentityTests.swift (~6 tests)

- `testMatchesBundleID` — bundleID set, candidate matches
- `testBundleIDMismatch` — bundleID set, candidate differs → false
- `testMatchesExactPath` — path == executablePath
- `testMatchesPathSuffix` — path ends with /executablePath
- `testNoBundleIDFallsToPath` — bundleID nil, path matches
- `testNoMatchReturnsfalse` — neither bundle nor path match

### 2c: ThrottleRuleCodableTests.swift (~8 tests)

- `testThrottleActionStopRoundTrip` — encode/decode .stop
- `testThrottleActionThrottleToRoundTrip` — encode/decode .throttleTo(0.5)
- `testThrottleActionNotifyOnlyRoundTrip` — encode/decode .notifyOnly
- `testThrottleRuleRoundTrip` — full rule encode/decode preserves all fields
- `testDayOfWeekCodable` — encode/decode DayOfWeek
- `testTimeOfDayCodable` — encode/decode TimeOfDay
- `testTimeOfDayIsBeforeOrEqual` — comparison logic
- `testThrottleScheduleRoundTrip` — schedule with days/times/invert

### 2d: ScheduleEvaluatorTests.swift (~8 tests)

The challenge: `ScheduleEvaluator.isActive()` uses `Date()` internally, making it time-dependent. Two approaches:
- **Option A**: Test at known times (fragile, depends on when tests run)
- **Option B**: Extract a `DateProviding` protocol (adds production code)
- **Option C**: Refactor `isActive` to accept `Date` parameter with default `Date()`

**Chosen: Option C** — add `date: Date = Date()` parameter. Zero behavior change for callers, fully testable.

Production change in `ScheduleEvaluator.swift`:
```swift
static func isActive(_ schedule: ThrottleSchedule, at date: Date = Date()) -> Bool {
```

Tests (using fixed dates):
- `testNormalRangeInside` — 10:00 within 09:00-17:00 on weekday → true
- `testNormalRangeOutside` — 20:00 outside 09:00-17:00 → false
- `testWrappingRangeAfterMidnight` — 02:00 within 22:00-06:00 → true
- `testWrappingRangeBeforeMidnight` — 23:00 within 22:00-06:00 → true
- `testWrappingRangeOutside` — 12:00 outside 22:00-06:00 → false
- `testDayMismatch` — right time but wrong day → false
- `testInvertedSchedule` — inside window + inverted → false
- `testInvertedOutsideWindow` — outside window + inverted → true

### 2e: SafetyListTests.swift (~6 tests)

- `testProtectedNames` — kernel_task, Lowbeer → true
- `testProtectedPaths` — /System/foo, /usr/libexec/bar → true
- `testSpecialPIDs` — PID 0, PID 1 → true
- `testOwnProcess` — current PID → true
- `testUnprotectedProcess` — "MyApp" at /Applications/... PID 500 → false
- `testUserAllowlist` — process matching allowlist entry → true

Note: SafetyList reads `LowbeerSettings.shared.userAllowlist`. For the allowlist test, we need to either:
- Accept the singleton coupling (test with whatever allowlist is set)
- Make SafetyList accept settings as parameter

**Chosen**: Add optional `settings` parameter to `isProtected()`:
```swift
static func isProtected(name:, path:, pid:, settings: LowbeerSettings = .shared) -> Bool
```

## Step 3: RuleEvaluator Tests (Tier 2)

### 3a: Production changes for testability

1. **ScheduleEvaluator**: Add `date` parameter (Step 2d above)
2. **SafetyList**: Add `settings` parameter (Step 2e above)
3. **LowbeerSettings**: Add internal init for tests:
```swift
// In LowbeerSettings.swift
init(forTesting: Bool) {
    self.globalCPUThreshold = 80
    self.sustainedSeconds = 30
    self.defaultAction = .stop
    self.throttleMode = .automatic
    self.pollInterval = 3
    self.launchAtLogin = false
    self.showInMenuBar = true
    self.notificationsEnabled = true
    self.isPaused = false
    self.rules = []
    self.userAllowlist = []
}
```
This avoids touching UserDefaults in tests. Mark `private` init as `private` and add `internal init(forTesting:)`.

4. **RuleEvaluator.evaluate()**: Accept optional settings parameter (already takes it). No change needed — it already takes `settings:` parameter.

### 3b: RuleEvaluatorTests.swift (~10 tests)

All tests use `LowbeerSettings(forTesting: true)` and construct ProcessInfo directly.

- `testSafetyListBlocksThrottle` — kernel_task returns nil
- `testPerAppRuleMatches` — rule with matching bundleID, above threshold, sustained → returns action
- `testPerAppRuleBelowThreshold` — matching rule but CPU below → nil
- `testPerAppRuleInsufficientDuration` — above threshold but not long enough → nil
- `testNoFallthroughToGlobal` — rule matches but threshold not met → nil (not global)
- `testGlobalThresholdFallback` — no matching rule, above global → defaultAction
- `testGlobalBelowThreshold` — no rule match, below global → nil
- `testForegroundSkip` — throttleInBackground + foreground → nil
- `testScheduleInactive` — rule with inactive schedule skipped, falls to next rule or global
- `testDisabledRuleSkipped` — rule.enabled=false → skipped

### 3c: Create MockForegroundObserver

For ThrottleEngine tests, we need a controllable foreground observer. Since ForegroundObserver is a class, we can subclass it (no protocol needed):

```swift
class MockForegroundObserver: ForegroundObserver {
    private var mockForegroundPID: pid_t = 0

    func setForeground(pid: pid_t) {
        mockForegroundPID = pid
    }

    override func isForeground(pid: pid_t) -> Bool {
        pid == mockForegroundPID
    }

    override func isForeground(bundleID: String?) -> Bool {
        false
    }
}
```

Wait — ForegroundObserver's `isForeground` methods aren't marked `open` or `class`, so they can't be overridden. We need a protocol.

**Protocol extraction:**
```swift
protocol ForegroundProviding: AnyObject {
    var foregroundPID: pid_t { get }
    var foregroundBundleID: String? { get }
    var onForegroundChanged: ((pid_t, String?) -> Void)? { get set }
    func isForeground(pid: pid_t) -> Bool
    func isForeground(bundleID: String?) -> Bool
}

extension ForegroundObserver: ForegroundProviding {}
```

Then ThrottleEngine changes from `ForegroundObserver` to `ForegroundProviding`:
```swift
init(monitor: ProcessMonitor, foreground: ForegroundProviding, settings: LowbeerSettings = .shared)
```

### 3d: ThrottleEngineTests.swift (~12 tests)

ThrottleEngine takes ProcessMonitor (concrete) — we can construct one with a custom pollInterval and inject mock processes directly.

Key: ThrottleEngine reads `monitor.processes` — we need to be able to set this. ProcessMonitor.processes is `private(set)` — accessible via `@testable import`.

Tests:
- `testPausedSkipsEvaluation` — isPaused=true → no sessions created
- `testBelowThresholdNoThrottle` — CPU 50%, threshold 80% → no session
- `testAboveThresholdCreatesSession` — CPU 100%, sustained 10 samples → session created
- `testDropsBelowThresholdResumes` — throttled process drops to 0% → session removed
- `testForegroundAutoResume` — throttled + foreground → session deactivated
- `testPIDReuseDetection` — session exists, process has different startTime → session removed
- `testDeadProcessCleanup` — session exists, PID not in processes → cleaned up
- `testResumeManual` — resume(pid:) removes session
- `testResumeAll` — clears all sessions
- `testAskFirstPrompts` — throttleMode=askFirst → no session, PID added to prompted
- `testNoFallthroughOnRuleMatch` — rule matches but threshold unmet → nil, not global
- `testNotifyOnlyNoSession` — notifyOnly action → session created then immediately removed

## Step 4: Xcode Project Integration

Generate or update `Lowbeer.xcodeproj` to include the test target. The project is generated via `xcodeproj` Ruby gem — check if a generation script exists.

```bash
# Check for existing generation script
ls /tmp/gen_xcodeproj.rb
```

If the script exists, add test target configuration to it. Otherwise, add the test target manually.

## Step 5: Verify All Tests Pass

```bash
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug test \
  -destination "platform=macOS" \
  -only-testing:LowbeerTests 2>&1 | tail -30
```

Expected: all ~65 tests pass, zero failures.

## Production Code Changes Summary

| File | Change | Reason |
|------|--------|--------|
| `ScheduleEvaluator.swift` | Add `at date: Date = Date()` param | Testable time |
| `SafetyList.swift` | Add `settings:` param with default | Testable allowlist |
| `LowbeerSettings.swift` | Add `init(forTesting:)` internal init | Test isolation |
| `ForegroundObserver.swift` | Extract `ForegroundProviding` protocol | Mock injection |
| `ThrottleEngine.swift` | Change foreground param to `ForegroundProviding` | Mock injection |

All changes are additive — existing call sites unchanged due to default parameters.

## Test Count Estimate

| File | Tests |
|------|-------|
| ProcessHistoryTests | 8 |
| AppIdentityTests | 6 |
| ThrottleRuleCodableTests | 8 |
| ScheduleEvaluatorTests | 8 |
| SafetyListTests | 6 |
| RuleEvaluatorTests | 10 |
| ThrottleEngineTests | 12 |
| **Total** | **~58** |

## Execution Order

1. Production code changes (protocol extraction, test inits)
2. Create test directory structure + mock files
3. Write Tier 1 tests (models + evaluators)
4. Write Tier 2 tests (RuleEvaluator + ThrottleEngine)
5. Add test target to Xcode project
6. Build and run all tests
7. Fix any failures
