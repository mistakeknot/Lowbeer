# Lowbeer

Open-source macOS process throttler. A menu bar app that monitors CPU usage and automatically stops or throttles runaway processes — the open-source alternative to App Tamer.

Named after Ainsley Lowbeer from William Gibson's *The Peripheral* — the systemic governor who dampens and corrects.

## The Problem

A runaway `zsh` process burns 98.5% CPU for six days. A background `node` process pegs a core while you're on battery. Chrome helper processes multiply. macOS doesn't stop them. App Tamer costs $15 and is closed-source. There's no good open-source alternative.

Now there is.

## What It Does

- **Monitors all processes** in real time via `proc_pidinfo` (same API Activity Monitor uses)
- **Automatically throttles** processes that exceed CPU thresholds using SIGSTOP/SIGCONT
- **Duty-cycle throttling** — limit a process to 25% CPU instead of fully stopping it
- **Per-app rules** — different thresholds and actions for different apps
- **Auto-resumes** when you switch to a throttled app (foreground detection)
- **Time-based schedules** — throttle only during work hours, or only at night
- **Safety list** — system processes (WindowServer, launchd, Finder, etc.) are never touched
- **Notifications** — get alerted when Lowbeer throttles something

## Quick Start

```bash
git clone https://github.com/mistakeknot/Lowbeer.git
cd Lowbeer
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Release build
```

Then open the built `.app` from DerivedData, or open `Lowbeer.xcodeproj` in Xcode and hit Run.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+
- Must run unsandboxed (sends SIGSTOP/SIGCONT to other processes)

## How It Works

Every 3 seconds, Lowbeer samples all running processes using `proc_pidinfo(PROC_PIDTASKINFO)` and computes CPU percentage from the delta in cumulative CPU nanoseconds. Processes exceeding the configured threshold for a sustained duration are throttled.

**Throttle actions:**
- **Stop** — `SIGSTOP` freezes the process entirely (0% CPU)
- **Throttle to X%** — duty-cycle alternating SIGSTOP/SIGCONT (e.g., 25% = run 250ms, stop 750ms per second)
- **Notify only** — send a macOS notification without throttling

**Safety:**
- System processes are hardcoded as never-throttle
- PID reuse is detected before every SIGSTOP (process name verification)
- Foreground apps are auto-resumed immediately
- All throttled processes are resumed on quit

## Configuration

**Settings window** (gear icon in the popover):

| Setting | Default | What it does |
|---------|---------|-------------|
| CPU threshold | 80% | Processes above this get throttled |
| Sustained duration | 30s | Must exceed threshold for this long |
| Default action | Stop | What happens when threshold is exceeded |
| Poll interval | 3s | How often to check processes |
| Launch at login | Off | Start automatically via SMAppService |

**Per-app rules** let you set custom thresholds and actions for specific applications.

**Allowlist** lets you add processes that should never be throttled, beyond the built-in safety list.

## Architecture

```
Lowbeer/
  App/          — SwiftUI @main, MenuBarExtra, AppDelegate
  Core/         — ProcessMonitor, ThrottleEngine, ForegroundObserver
  Models/       — ProcessInfo, ThrottleRule, Settings
  Views/        — Popover (process list + sparklines), Settings tabs
  Helpers/      — SafetyList, ProcessIcon
```

See `AGENTS.md` for the full development guide.

## License

MIT — see [LICENSE](LICENSE).
