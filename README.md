# Lowbeer

Maximize your MacBook battery life while vibecoding. A native macOS menu bar app that monitors CPU usage and automatically throttles runaway processes — the open-source alternative to App Tamer, built for the AI coding era.

Named after Ainsley Lowbeer from William Gibson's *The Peripheral* — the systemic governor who dampens and corrects.

## The Problem

You're vibecoding on your MacBook Pro. Claude Code is spinning up subprocesses, Cursor has three language servers running, Ollama is doing local inference in the background. Your fans ramp, your battery drains from 80% to 30% in an hour. macOS doesn't manage this. App Tamer costs $15 and is closed-source.

Now there's a free, open-source alternative.

## Install

**Download the DMG** from [GitHub Releases](https://github.com/mistakeknot/Lowbeer/releases), open it, drag Lowbeer to Applications.

First launch: right-click the app and select Open (ad-hoc signed, no Developer ID yet).

**Build from source:**
```bash
git clone https://github.com/mistakeknot/Lowbeer.git
cd Lowbeer
./scripts/package.sh --release
# → build/Lowbeer-0.1.0.dmg
```

## What It Does

- **Monitors all processes** in real time via `proc_pidinfo` (same API Activity Monitor uses)
- **Automatically throttles** processes that exceed CPU thresholds using SIGSTOP/SIGCONT
- **Duty-cycle throttling** — limit a process to 25% CPU instead of fully stopping it
- **Per-app rules** — different thresholds and actions for different apps
- **Auto-resumes** when you switch to a throttled app (foreground detection)
- **Time-based schedules** — throttle only during work hours, or only at night
- **Safety list** — system processes (WindowServer, launchd, Finder, etc.) are never touched
- **Notifications** — get alerted when Lowbeer throttles something

## Requirements

- macOS 14 (Sonoma) or later on Apple Silicon
- Must run unsandboxed (sends SIGSTOP/SIGCONT to other processes)
- Xcode 15+ (for building from source)

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

## Roadmap

See [`docs/lowbeer-roadmap.md`](docs/lowbeer-roadmap.md) for the full plan. Highlights:

- **v1.0** — Smart defaults for AI tools (Claude Code, Cursor, Copilot, Ollama), battery savings counter, process offender leaderboard
- **v2.0** — Apple Silicon E-core demotion via `taskpolicy` (slow processes down instead of freezing them), thermal-aware throttling
- **v3.0** — Community AI tool profiles, real power telemetry, privileged helper

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
