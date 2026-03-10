# Agent Instructions — Lowbeer

Open-source macOS process throttler. Menu bar app that monitors CPU usage via `proc_pidinfo` and throttles runaway processes using SIGSTOP/SIGCONT.

> Detailed docs are split into topic files under `agents/`. This file is the index.

## Quick Reference

```bash
# Build (debug)
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build

# Build release + DMG
./scripts/package.sh --release
# → build/Lowbeer-<version>.dmg

# Run (after debug build)
open ~/Library/Developer/Xcode/DerivedData/Lowbeer-*/Build/Products/Debug/Lowbeer.app

# Test throttle detection (creates 100% CPU process)
yes > /dev/null &
# ... verify Lowbeer detects and throttles it ...
kill %1

# Regenerate xcodeproj after adding/removing Swift files
ruby /tmp/gen_xcodeproj.rb
```

## Architecture Overview

```
LowbeerApp (@main, MenuBarExtra .window)
├── ProcessMonitor            — 3s poll, proc_pidinfo CPU deltas
├── ThrottleEngine            — Rule evaluation → SIGSTOP/SIGCONT
│   ├── RuleEvaluator         — Per-app + global threshold matching
│   ├── ScheduleEvaluator     — Time-of-day schedule matching
│   └── ThrottleSession       — Per-process state (full stop / duty-cycle)
├── ForegroundObserver        — NSWorkspace activation watcher
├── NotificationManager       — UNUserNotificationCenter
├── LowbeerSettings           — UserDefaults + JSON file persistence
└── UI
    ├── PopoverView           — Process list with sparklines
    ├── ProcessRowView        — Icon, name, CPU%, sparkline, throttle button
    ├── SparklineView         — 60-sample Canvas line chart
    └── Settings (3 tabs)     — General, Rules, Allowlist
```

## Directory Layout

| Path | What |
|------|------|
| `Lowbeer/App/` | `LowbeerApp.swift` (@main, MenuBarExtra), `AppDelegate.swift` (lifecycle) |
| `Lowbeer/Core/` | ProcessMonitor, ProcessSnapshot, ThrottleEngine, ThrottleSession, RuleEvaluator, ScheduleEvaluator, ForegroundObserver, NotificationManager |
| `Lowbeer/Models/` | ProcessInfo, ThrottleRule, AppIdentity, ProcessHistory, LowbeerSettings |
| `Lowbeer/Views/MenuBar/` | PopoverView, ProcessRowView, SparklineView |
| `Lowbeer/Views/Settings/` | SettingsView, GeneralSettingsView, RulesSettingsView, AllowlistView |
| `Lowbeer/Helpers/` | SafetyList, ProcessIcon, HelpWindowController, SettingsWindowController |
| `agents/` | Topic guides (architecture, monitoring, throttling, safety, testing) |
| `docs/` | Vision, PRD, roadmap, CUJs, brainstorms |
| `scripts/` | `package.sh` — build + DMG packaging |
| `.github/workflows/` | `release.yml` — automated release on version tags |

## Topic Guides

| Guide | What's in it |
|-------|-------------|
| [Architecture](agents/architecture.md) | Component diagram, directory tree, file responsibilities, persistence |
| [Monitoring](agents/monitoring.md) | CPU sampling via libproc, delta calculation, poll cycle, gotchas |
| [Throttling](agents/throttling.md) | SIGSTOP/SIGCONT mechanics, duty-cycle, rule evaluation, auto-resume |
| [Safety](agents/safety.md) | Protected processes, PID verification, quit cleanup, failure modes |
| [Testing](agents/testing.md) | Manual test procedures for throttling, foreground resume, persistence |

## Build & Release

**Local packaging:**
```bash
./scripts/package.sh --release    # → build/Lowbeer-<version>.dmg
./scripts/package.sh --debug      # → debug build DMG
```

**Automated releases** (GitHub Actions):
1. Bump `MARKETING_VERSION` in `Lowbeer.xcodeproj/project.pbxproj`
2. Commit and tag: `git tag v0.2.0 && git push --tags`
3. CI builds on `macos-14` runner, creates DMG, publishes GitHub Release

**Current signing:** Ad-hoc (no Developer ID). Users must right-click → Open on first launch.

## Key Design Decisions (Do Not Re-Ask)

- **SIGSTOP/SIGCONT, not Mach task_suspend** — no entitlements needed
- **No privileged helper in v1** — same-user processes cover 95% of cases
- **CPU % as energy proxy** — no public API for real energy impact
- **ProcessInfo name collision** — use `Foundation.ProcessInfo` for system ProcessInfo
- **libproc constants** — `PROC_PIDPATHINFO_MAXSIZE` hardcoded as 4096 (not bridged to Swift)
- **Trunk-based development** — commit directly to `main`
- **Unsandboxed** — required for SIGSTOP/SIGCONT; distributed outside App Store

## Persistence

- **UserDefaults** — global settings (threshold, interval, action, launch at login, notifications)
- **JSON files** in `~/Library/Application Support/Lowbeer/`:
  - `lowbeer_rules.json` — per-app rules
  - `lowbeer_allowlist.json` — user allowlist
- Settings auto-save on property change via `didSet`

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs or other tracking methods.

```bash
bd ready              # Show unblocked work
bd list               # All issues with dependency tree
bd show <id>          # Issue details
bd create --title="Summary" --description="Context" --type=task --priority=2
bd update <id> --status=in_progress
bd close <id>         # Mark complete
```

Issue types: `bug`, `feature`, `task`, `epic`, `chore`
Priorities: `0` (critical) → `4` (backlog)

## Landing the Plane (Session Completion)

**When ending a work session**, complete ALL steps. Work is NOT complete until `git push` succeeds.

1. **File issues** for remaining work (`bd create`)
2. **Run quality gates** if code changed (build, tests)
3. **Update issue status** — close finished, update in-progress
4. **Push**:
   ```bash
   git pull --rebase && git push
   git status  # MUST show "up to date with origin"
   ```
5. **Verify** — all changes committed AND pushed
<!-- END BEADS INTEGRATION -->
