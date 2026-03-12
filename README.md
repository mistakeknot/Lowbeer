# Lowbeer

Maximize your MacBook battery life while vibecoding. A native macOS menu bar app that monitors CPU usage, shows live system power draw, and automatically throttles runaway processes — the open-source alternative to App Tamer, built for the AI coding era.

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
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Release build
```

## What It Does

### Live Energy Monitoring

Lowbeer reads real-time power data from your Apple Silicon chip using IOReport hardware counters — the same data source as `powermetrics`. The menu bar shows:

- **System wattage** — a colored bolt icon (`⚡ 4.2W`) showing total CPU + GPU + ANE + DRAM power draw
- **Color-coded severity** — green (< 5W), yellow (5–10W), orange (10–20W), red (> 20W)
- **Idle mode** — just a green `⚡` when draw is under 3W, keeping the menu bar clean

Click the menu bar icon to open the popover, which shows:

- **Top 15 processes** sorted by CPU usage
- **Per-process energy share** — each process shows what percentage of system power it's responsible for (e.g., `42%⚡`)
- **CPU sparklines** — mini graphs showing recent CPU history per process
- **One-click throttle/resume** buttons per process

On Intel Macs, Lowbeer falls back to showing CPU percentage (IOReport is Apple Silicon only).

### Automatic Throttling

Lowbeer ships with **14 pre-configured rules** for common vibecoding tools. Out of the box, it knows how to handle:

| Category | Apps | Threshold | Action |
|----------|------|-----------|--------|
| **Terminals** | Ghostty, Warp, iTerm2, Terminal, Kitty, Alacritty | 150% CPU for 30s | Duty-cycle to 50%, background only |
| **AI Editors** | Cursor, VS Code, Windsurf | 120% CPU for 60s | Duty-cycle to 50%, background only |
| **Build Tools** | Node.js, Python | 150% CPU for 45s | Duty-cycle to 50% |
| **Local LLMs** | Ollama, LM Studio | 300% CPU for 120s | Notify only |

Custom rules you create always take priority over defaults.

### Manual Controls

- **Pause/resume all** — one button to pause all throttling
- **Per-process throttle** — click the pause icon on any process to stop it immediately
- **Per-process resume** — click play to resume a throttled process
- **Quit** — `✕` button in the popover header

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon recommended (for live power monitoring)
- Intel Macs supported (falls back to CPU percentage display)
- Runs unsandboxed (required to send SIGSTOP/SIGCONT to other processes)

## How It Works

### CPU Monitoring

Every 3 seconds, Lowbeer samples all running processes using `proc_pidinfo(PROC_PIDTASKINFO)` and computes CPU percentage from the delta in cumulative CPU nanoseconds. Processes exceeding the configured threshold for a sustained duration trigger the configured action.

### Power Measurement

On Apple Silicon, Lowbeer reads hardware energy counters via IOReport (a private Apple framework accessed through `dlsym`). It subscribes to the "Energy Model" channel group and computes per-subsystem wattage:

- **CPU** — P-cluster and E-cluster power separately
- **GPU** — integrated GPU power
- **ANE** — Neural Engine power
- **DRAM** — memory subsystem power

Energy values (in nanojoules) are converted to watts by dividing by the sampling interval. This gives the same readings as `sudo powermetrics` but without requiring root.

### Per-Process Energy Estimation

There's no public macOS API for per-process power. Lowbeer estimates each process's share by proportional CPU attribution: if a process uses 60% of total CPU and the system draws 10W, it's attributed ~6W. This is approximate (doesn't account for P-core vs E-core efficiency) but accurate for relative ranking — which is what matters for "why is my battery dying?"

### Throttle Actions

- **Stop** — `SIGSTOP` freezes the process entirely (0% CPU)
- **Throttle to X%** — duty-cycle alternating SIGSTOP/SIGCONT (e.g., 50% = run 500ms, stop 500ms per second)
- **Notify only** — send a macOS notification without throttling

### Safety

- **System processes** are hardcoded as never-throttle (WindowServer, launchd, Finder, Dock, etc.)
- **PID reuse detection** — process start time is verified before every SIGSTOP to prevent throttling a new process that reused a stale PID
- **Zombie filtering** — dead processes are skipped during sampling
- **Foreground auto-resume** — switching to a throttled app resumes it immediately
- **Clean exit** — all throttled processes are resumed when Lowbeer quits

## Configuration

**Settings window** (gear icon in the popover):

| Setting | Default | What it does |
|---------|---------|-------------|
| CPU threshold | 80% | Global threshold — processes above this get throttled |
| Sustained duration | 30s | Must exceed threshold for this long before action triggers |
| Default action | Stop | What happens when threshold is exceeded |
| Poll interval | 3s | How often to sample processes and power |
| Launch at login | Off | Start automatically via SMAppService |

**Per-app rules** let you set custom thresholds and actions for specific applications. Custom rules always evaluate before built-in defaults.

**Allowlist** lets you add processes that should never be throttled, beyond the built-in safety list.

## Architecture

```
Lowbeer/
  App/          — SwiftUI @main, MenuBarExtra, AppDelegate
  Core/         — ProcessMonitor, PowerSampler, ThrottleEngine, ForegroundObserver
  Models/       — ProcessInfo, ThrottleRule, DefaultRules, Settings
  Views/        — Popover (process list + sparklines + energy), Settings tabs
  Helpers/      — SafetyList, ProcessIcon
```

Key components:

- **ProcessMonitor** — polls CPU usage and power on a 3s timer, drives the UI
- **PowerSampler** — IOReport bindings via `dlsym`, converts energy deltas to watts
- **ThrottleEngine** — evaluates rules against process state, dispatches SIGSTOP/SIGCONT
- **DefaultRules** — 14 pre-built rules for vibecoding tools, seeded on first launch

See `AGENTS.md` for the full development guide.

## License

MIT — see [LICENSE](LICENSE).
