# Lowbeer Initial Goals Brainstorm

**Date:** 2026-03-06
**Scope:** v1.0 release planning — three concurrent goal streams

---

## Stream 1: Ship v1.0 Public Release

### What "v1.0" means
- Feature-complete for core use case: monitor, throttle, configure, notify
- Polished UI with no rough edges in popover or settings
- Public GitHub repo with proper README, LICENSE, install instructions
- Release build signed for distribution outside App Store
- Homebrew cask or DMG download for easy installation

### Key deliverables
- GitHub remote configured and pushed
- Release workflow (xcodebuild archive, notarization, DMG packaging)
- Version numbering and changelog
- Landing page or enhanced README with screenshots
- Launch at login via SMAppService verified working

---

## Stream 2: Advanced Features

### Energy Impact integration
- macOS doesn't expose a public API for per-process energy impact
- Could approximate via CPU% + IO + GPU usage (IOKit?)
- App Tamer shows "Energy Impact" — reverse-engineer what they sample?
- Alternative: use `powermetrics` output parsing (requires root)

### Privileged helper for root processes
- Currently limited to same-user processes (covers ~95% of cases)
- SMJobBless or XPC service for privileged operations
- Allows throttling root-owned processes (launchd children, daemons)
- Complexity vs. value tradeoff — defer to v1.1?

### Menu bar enhancements
- SparklineView already exists — ensure it's polished
- Show system-wide CPU in menu bar icon (tiny chart or percentage)
- Quick-access to top CPU consumers from menu bar

### Auto-update
- Sparkle framework for self-updating
- Check for updates on launch, weekly, or manually
- Signed updates with Ed25519

---

## Stream 3: Stabilize and Harden

### PID reuse safety
- Current approach: verify process name before SIGSTOP
- Edge case: rapid PID reuse within one poll interval
- Add process start time verification (kinfo_proc -> p_starttime)
- Consider tracking (pid, starttime) tuples instead of just pid

### Automated testing
- XCTest for model layer (ProcessInfo, ThrottleRule, settings serialization)
- Mock-based testing for ThrottleEngine (inject fake process list)
- Integration test: launch helper process, verify throttle, verify resume
- CI via GitHub Actions with macOS runner

### Permissions handling
- Graceful degradation when denied process access
- Clear user-facing explanation of why unsandboxed
- Handle System Settings > Privacy > Automation prompts

### Edge cases to fix
- Zombie processes (state = Z) — skip in monitoring
- Very short-lived processes appearing/disappearing between polls
- Multiple rapid SIGSTOP/SIGCONT to same PID (debounce)
- App quit during active duty-cycle (ensure cleanup)

---

## Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| GitHub release workflow | High | Medium | P1 |
| Automated tests (core) | High | Medium | P1 |
| PID reuse hardening | High | Low | P1 |
| Menu bar polish | Medium | Low | P1 |
| Homebrew cask | Medium | Low | P2 |
| Auto-update (Sparkle) | Medium | Medium | P2 |
| Energy Impact proxy | Medium | High | P3 |
| Privileged helper | Low | High | P3 |
