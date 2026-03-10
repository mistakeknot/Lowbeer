# Lowbeer — Roadmap

**Last updated:** 2026-03-06
**PRD:** [`docs/PRD.md`](PRD.md)
**Vision:** [`docs/lowbeer-vision.md`](lowbeer-vision.md)

---

## Phase 1: v1.0 Release (current)

Ship a polished, distributable release with hardened safety.

| Item | Priority | Status |
|------|----------|--------|
| PID start-time verification for reuse safety | P1 | Planned |
| XCTest suite for models (ProcessInfo, ThrottleRule, settings) | P1 | Planned |
| Mock-based ThrottleEngine tests | P1 | Planned |
| GitHub remote + initial push | P1 | Planned |
| Signed release build (xcodebuild archive + notarization) | P1 | Planned |
| DMG packaging for download | P1 | Planned |
| Menu bar polish (system CPU display, icon refinement) | P1 | Planned |
| Launch-at-login verification (SMAppService) | P1 | Planned |
| Zombie process filtering (skip state=Z) | P1 | Planned |
| SIGSTOP debounce for rapid PID events | P1 | Planned |

**Exit criteria:** Downloadable DMG, automated tests passing, no known safety bugs.

## Phase 2: Distribution & Polish

Make Lowbeer easy to install and keep updated.

| Item | Priority | Status |
|------|----------|--------|
| Homebrew cask formula | P2 | Planned |
| Sparkle auto-update integration | P2 | Planned |
| GitHub Actions CI (build + test on macOS runner) | P2 | Planned |
| Changelog and version numbering | P2 | Planned |
| README screenshots and install guide | P2 | Planned |
| Permissions handling (graceful degradation) | P2 | Planned |

**Exit criteria:** `brew install --cask lowbeer` works, auto-update delivers patches.

## Phase 3: Advanced Throttling

Smarter throttling decisions and broader process coverage.

| Item | Priority | Status |
|------|----------|--------|
| Energy Impact proxy (CPU + IO approximation) | P3 | Planned |
| Privileged helper (SMJobBless/XPC) for root processes | P3 | Planned |
| Adaptive thresholds based on power source (battery vs. AC) | P3 | Planned |
| Community rule sets for common offenders | P3 | Planned |
| Integration test suite (real process launch + throttle) | P3 | Planned |

**Exit criteria:** Energy column in popover, root process throttling opt-in.

---

## Completed

All core monitoring, throttling, configuration, and notification features are shipped and functional. See [PRD Section 3](PRD.md#3-core-capabilities) for the full list.
