# PRD: Automated Test Suite (Models + Throttle Engine)

**Bead:** Lowbeer-p5i
**Date:** 2026-03-11
**Priority:** P1

## Problem Statement

Lowbeer has no automated tests. Every change requires manual testing (spawn CPU-heavy process, observe throttle behavior). This blocks confident refactoring and feature development. The core logic — rule evaluation, CPU calculation, ring buffers, safety checks — is pure and highly testable, yet untested.

## Goals

1. **XCTest target** integrated into the Xcode project build
2. **Tier 1 coverage**: Pure unit tests for all models and evaluators (~36 tests)
3. **Tier 2 coverage**: Logic tests for RuleEvaluator and ThrottleEngine with mock dependencies (~27 tests)
4. **Minimal production code changes** — add protocols only where mocking requires it

## Non-Goals

- CI pipeline setup (future work)
- UI/view testing
- Tier 3 integration tests (SIGSTOP on real processes — manual only)
- Code coverage enforcement tooling

## Technical Approach

### Test Target

- Add `LowbeerTests` directory with XCTest files
- Regenerate `Lowbeer.xcodeproj` to include test target
- `@testable import Lowbeer` for internal access

### Protocol Extraction (Tier 2 only)

Three minimal protocols for mockability:

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

Production types gain conformance via extensions. Default parameter injection keeps call sites unchanged.

### Test Organization

```
LowbeerTests/
  Models/
    ProcessHistoryTests.swift      — ring buffer
    AppIdentityTests.swift         — matching logic
    ThrottleRuleTests.swift        — Codable, identity
    ThrottleActionTests.swift      — Codable enum
    ScheduleEvaluatorTests.swift   — time windows
  Core/
    SafetyListTests.swift          — protection checks
    RuleEvaluatorTests.swift       — rule precedence
    ThrottleEngineTests.swift      — state machine
  Mocks/
    MockProcessSampler.swift
    MockSignalSender.swift
    MockForegroundObserver.swift
```

## Deliverables

| # | Deliverable | Acceptance |
|---|-------------|------------|
| 1 | LowbeerTests target builds with `xcodebuild test` | Exit code 0 |
| 2 | ProcessHistory tests pass | 8+ tests, ring buffer correctness |
| 3 | AppIdentity tests pass | 6+ tests, matching edge cases |
| 4 | ThrottleRule + ThrottleAction Codable tests pass | 8+ tests |
| 5 | ScheduleEvaluator tests pass | 8+ tests, wrapping/inverted |
| 6 | SafetyList tests pass | 6+ tests, names/paths/PIDs |
| 7 | RuleEvaluator tests pass (with mocks) | 10+ tests, precedence/fallthrough |
| 8 | ThrottleEngine tests pass (with mocks) | 12+ tests, state machine |
| 9 | Protocol extraction (3 protocols) | Existing code compiles unchanged |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| xcodeproj regeneration breaks test target | Medium | High | Add test target to gen script |
| @testable import signing issues | Low | Medium | Debug config only |
| Protocol extraction cascading changes | Low | Medium | Default parameter injection |

## Success Criteria

- `xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug test` passes
- 60+ tests total across Tier 1 and Tier 2
- Zero production behavior changes
