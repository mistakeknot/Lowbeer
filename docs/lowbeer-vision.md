# Lowbeer — Vision

**Last updated:** 2026-03-06
**Philosophy:** [`PHILOSOPHY.md`](../PHILOSOPHY.md)
**Brainstorm:** [`docs/brainstorms/2026-03-06-lowbeer-initial-goals.md`](brainstorms/2026-03-06-lowbeer-initial-goals.md)

---

## The Big Idea

Your computer should not waste your battery, spin your fans, and lag your UI because a background process decided to burn 100% of a core for six days. macOS doesn't stop this. App Tamer costs $15 and is closed-source. Lowbeer is the free, open-source systemic governor — it monitors every process in real time and automatically throttles the ones that are out of line, using the same SIGSTOP/SIGCONT mechanism the kernel uses. Named after Ainsley Lowbeer from Gibson's *The Peripheral*, it dampens and corrects without overreach.

## Design Principles

1. **Do No Harm** — Never throttle a process that could destabilize the system. The safety list is non-negotiable; one wrong SIGSTOP can freeze a desktop.

2. **Transparent by Default** — Every throttle action is visible and instantly reversible. No silent, hidden behavior. Users always know what Lowbeer is doing.

3. **Zero Configuration Works** — Sensible defaults (80% threshold, 30s sustained) cover 90% of use cases. Power users can customize, but the app should work well out of the box.

4. **Native and Minimal** — A SwiftUI menu bar app using system APIs directly (libproc, SIGSTOP/SIGCONT). No Electron, no frameworks, negligible resource usage. Lowbeer should never become the problem it solves.

5. **Open Source First** — MIT license, public repo, community contributions welcome. This functionality should be free and inspectable.

## Current State

- **Version:** Pre-release (targeting v1.0)
- **Maturity:** Core functionality complete — monitoring, throttling, duty-cycle, rules, settings, notifications
- **Architecture:** 26 Swift files across 5 modules (App, Core, Models, Views, Helpers)
- **Platform:** macOS 14+ (Sonoma), unsandboxed, Swift 5.9 with SwiftUI
- **Distribution:** Build from source only (no signed release yet)

**Key milestones achieved:**
- CPU monitoring via proc_pidinfo with delta calculation
- SIGSTOP/SIGCONT throttling with duty-cycle support
- Per-app rules with custom thresholds and actions
- Foreground detection with auto-resume
- Time-based scheduling
- Safety list protecting system processes
- Settings persistence via UserDefaults + JSON
- Menu bar UI with sparkline charts

## Where We're Going

### Near-term: Ship v1.0 (next 2-4 weeks)
Polish what exists and get it into users' hands. GitHub remote, signed release build, DMG packaging, Homebrew cask. Harden PID reuse safety (start-time verification). Add automated tests for the core model and throttle engine. Make launch-at-login bulletproof via SMAppService.

### Medium-term: Advanced throttling (1-3 months)
Improve the intelligence of throttling decisions. Approximate Energy Impact via CPU + IO sampling. Polish the menu bar with system-wide CPU display. Add Sparkle for auto-updates so users don't have to manually download new versions.

### Long-term: Full system governor (3-6 months)
Privileged helper (SMJobBless/XPC) to throttle root-owned processes. Machine learning for adaptive thresholds based on usage patterns. Community-contributed rule sets for common offenders. Become the definitive open-source process governor for macOS.

## What We Believe

These are the bets Lowbeer makes. If any prove wrong, the direction changes.

1. **CPU percentage is a good-enough proxy for energy impact.** There's no public API for per-process energy. If Apple exposes one, we'd adopt it immediately, but until then, CPU% covers the cases users care about.

2. **Same-user processes cover 95% of the problem.** Most runaway processes (Chrome helpers, node, zsh, Xcode builds) run as the logged-in user. A privileged helper is nice-to-have, not essential for v1.

3. **SIGSTOP/SIGCONT is the right mechanism.** It requires no entitlements, no kernel extensions, no SIP bypass. It's what the kernel uses. The tradeoff is that some apps handle SIGSTOP poorly — but the safety list and foreground detection mitigate this.

4. **Users want set-and-forget, not a dashboard.** Lowbeer is not Activity Monitor. The goal is autonomous operation with notifications, not a process management UI. The popover exists to explain what's happening, not to be a daily tool.

5. **Open source wins in utilities.** For a tool this close to the OS, users want to inspect the code. The $15 App Tamer market proves demand; open source proves trustworthiness.
