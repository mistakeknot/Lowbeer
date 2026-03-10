# Lowbeer — Product Requirements Document

**Version:** Pre-release (targeting v1.0)
**Last updated:** 2026-03-06
**Status:** Living document — regenerate with `/interpath:prd`
**Vision:** [`docs/lowbeer-vision.md`](lowbeer-vision.md)

---

## 1. Problem Statement

A runaway `zsh` process burns 98.5% CPU for six days. A background `node` process pegs a core while you're on battery. Chrome helper processes multiply. macOS does not automatically stop any of them.

**Who experiences this:** Every Mac user, but especially developers and power users who run many background processes (build tools, language servers, browsers with many tabs).

**Current alternative:** App Tamer ($15, closed-source). There is no good open-source alternative. Activity Monitor shows the problem but doesn't fix it. Users must manually find and kill runaway processes.

**Lowbeer's answer:** An open-source, set-and-forget menu bar app that monitors CPU usage and automatically throttles runaway processes — the systemic governor macOS is missing.

## 2. Product Overview

Lowbeer is a native macOS menu bar application built with Swift 5.9 and SwiftUI. It polls all running processes every 3 seconds via `proc_pidinfo(PROC_PIDTASKINFO)`, computes CPU percentage from delta nanoseconds, and automatically throttles processes exceeding configured thresholds using SIGSTOP/SIGCONT.

**Component summary:**
- 26 Swift source files across 5 modules
- App (2 files): entry point, AppDelegate
- Core (7 files): ProcessMonitor, ThrottleEngine, ThrottleSession, RuleEvaluator, ScheduleEvaluator, ForegroundObserver, NotificationManager, ProcessSnapshot
- Models (4 files): ProcessInfo, ThrottleRule, LowbeerSettings, ProcessHistory, AppIdentity
- Views (6 files): PopoverView, ProcessRowView, SparklineView, SettingsView, GeneralSettingsView, RulesSettingsView, AllowlistView
- Helpers (3 files): SafetyList, ProcessIcon, HelpWindowController, SettingsWindowController

**Target user:** Mac developers and power users who want automatic CPU management without manual intervention. Comfortable with menu bar apps, may never open Settings.

## 3. Core Capabilities

### 3.1 Monitoring
| Capability | Description | Status |
|-----------|-------------|--------|
| CPU sampling | 3s polling via `proc_pidinfo`, delta calculation for accurate % | Shipped |
| Process discovery | Enumerates all user-owned processes each interval | Shipped |
| Sparkline charts | Per-process CPU history in the menu bar popover | Shipped |
| Process icons | App icon resolution for identified processes | Shipped |

### 3.2 Throttling
| Capability | Description | Status |
|-----------|-------------|--------|
| Full stop | SIGSTOP freezes process to 0% CPU | Shipped |
| Duty-cycle | Alternating SIGSTOP/SIGCONT for partial throttle (e.g., 25%) | Shipped |
| Foreground resume | Auto-resume when user switches to throttled app | Shipped |
| PID verification | Name check before every SIGSTOP to prevent PID reuse errors | Shipped |
| Quit cleanup | Resume all throttled processes on app exit | Shipped |

### 3.3 Configuration
| Capability | Description | Status |
|-----------|-------------|--------|
| Global threshold | CPU % above which processes get throttled (default: 80%) | Shipped |
| Sustained duration | Process must exceed threshold for this long (default: 30s) | Shipped |
| Per-app rules | Custom thresholds and actions per application | Shipped |
| Time schedules | Throttle only during specific hours | Shipped |
| Allowlist | User-defined never-throttle list | Shipped |
| Safety list | Hardcoded system process protection | Shipped |
| Settings persistence | UserDefaults + JSON serialization | Shipped |

### 3.4 Notifications
| Capability | Description | Status |
|-----------|-------------|--------|
| Throttle alerts | macOS notification when a process is throttled | Shipped |
| Notify-only action | Alert without throttling for monitored processes | Shipped |

### 3.5 Planned (v1.0+)
| Capability | Description | Priority |
|-----------|-------------|----------|
| PID start-time verification | Track (pid, starttime) tuples for reuse safety | P1 |
| Automated tests | XCTest for models and mock-based engine tests | P1 |
| Release build | Signed, notarized DMG for distribution | P1 |
| Homebrew cask | `brew install --cask lowbeer` | P2 |
| Auto-update (Sparkle) | Self-updating with Ed25519 signatures | P2 |
| Energy Impact proxy | Approximate energy via CPU + IO | P3 |
| Privileged helper | SMJobBless/XPC for root process throttling | P3 |

## 4. Architecture

### 4.1 Module Structure

```
Lowbeer/
  App/        SwiftUI @main, MenuBarExtra (.window), AppDelegate
  Core/       ProcessMonitor → ThrottleEngine → ThrottleSession
              RuleEvaluator, ScheduleEvaluator, ForegroundObserver
              NotificationManager, ProcessSnapshot
  Models/     ProcessInfo, ThrottleRule, LowbeerSettings
              ProcessHistory, AppIdentity
  Views/      MenuBar/ (PopoverView, ProcessRowView, SparklineView)
              Settings/ (SettingsView, GeneralSettingsView,
                        RulesSettingsView, AllowlistView)
  Helpers/    SafetyList, ProcessIcon, window controllers
```

### 4.2 Data Flow

```
proc_pidinfo (every 3s)
  → ProcessMonitor (delta calc → CPU %)
    → RuleEvaluator (threshold + schedule check)
      → ThrottleEngine (SIGSTOP/SIGCONT dispatch)
        → ThrottleSession (per-process state)

ForegroundObserver ──→ ThrottleEngine (auto-resume)
NotificationManager ←── ThrottleEngine (alerts)
```

### 4.3 Platform Requirements
- macOS 14+ (Sonoma) — @Observable, MenuBarExtra
- Unsandboxed — SIGSTOP/SIGCONT requires direct process access
- No entitlements — same-user processes only
- Xcode project (generated via `xcodeproj` gem, not SPM)

## 5. Non-Goals

- **Not a task manager.** Activity Monitor already exists. Lowbeer shows processes only to explain what it's throttling.
- **Not a system optimizer.** No memory cleaning, startup management, or kernel tuning.
- **Not cross-platform.** macOS-specific by design. SIGSTOP/SIGCONT and libproc are the right tools for this platform.
- **Not an App Store app.** Unsandboxed by necessity; distributed independently.
- **Not a dashboard.** Users should set it and forget it. The popover explains, it doesn't demand attention.

## 6. Success Metrics

### Quantitative
- Core features shipped: 14/14 (monitoring, throttling, config, notifications)
- Source files: 26 Swift files
- Automated test coverage: 0% (P1 gap — target: model + engine coverage)
- Release builds: 0 (P1 gap — target: signed DMG)

### Qualitative
- Zero-config experience works for default use case
- No reports of incorrect throttling (safety list + PID verification)
- Menu bar UI is responsive and non-intrusive
- Settings changes persist correctly across launches

## 7. Open Questions

1. **Energy Impact proxy accuracy** — Can CPU% + IO approximation match Activity Monitor's Energy column closely enough to be useful?
2. **Privileged helper scope** — Is SMJobBless the right path, or should v1.1 use an XPC service? What's the UX for the privilege escalation prompt?
3. **Automated test strategy** — Should integration tests launch real helper processes, or is mock-based testing sufficient for the throttle engine?
4. **Distribution channel** — DMG from GitHub Releases vs. Homebrew cask vs. both?
5. **Zombie process handling** — Skip silently, or surface to user as "process exited while throttled"?
