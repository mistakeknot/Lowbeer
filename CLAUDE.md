# Lowbeer

> See `AGENTS.md` for full development guide (architecture, safety model, throttle mechanics).

## Overview

Open-source macOS process throttler. Menu bar app that monitors CPU usage and automatically throttles runaway processes via SIGSTOP/SIGCONT. Named after Ainsley Lowbeer from Gibson's *The Peripheral*.

## Quick Commands

```bash
# Build
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build

# Run (after build)
open ~/Library/Developer/Xcode/DerivedData/Lowbeer-*/Build/Products/Debug/Lowbeer.app

# Test throttle detection (creates 100% CPU process)
yes > /dev/null &
# ... verify Lowbeer detects and throttles it ...
kill %1

# Regenerate xcodeproj (after adding/removing files)
ruby /tmp/gen_xcodeproj.rb
```

## Tech Stack

- **Swift 5.9** — SwiftUI lifecycle, @Observable, MenuBarExtra (.window style)
- **macOS 14+ (Sonoma)** — minimum deployment target
- **Unsandboxed** — required for SIGSTOP/SIGCONT; distributed outside App Store
- **proc_pidinfo(PROC_PIDTASKINFO)** — CPU time sampling via libproc
- **Xcode project** — generated via `xcodeproj` Ruby gem, not SPM

## Key Paths

| Path | What |
|------|------|
| `Lowbeer/Core/ProcessMonitor.swift` | CPU polling engine (3s timer, delta calc) |
| `Lowbeer/Core/ThrottleEngine.swift` | Rule evaluation + SIGSTOP/SIGCONT dispatch |
| `Lowbeer/Core/ThrottleSession.swift` | Per-process throttle state (full stop or duty-cycle) |
| `Lowbeer/Models/LowbeerSettings.swift` | UserDefaults + JSON persistence singleton |
| `Lowbeer/Helpers/SafetyList.swift` | Hardcoded never-throttle list |

## Design Decisions (Do Not Re-Ask)

- **SIGSTOP/SIGCONT, not Mach task_suspend** — no entitlements needed, works for same-user processes
- **No privileged helper in v1** — same-user processes cover 95% of use cases
- **CPU % as energy proxy** — no public API for real energy impact
- **ProcessInfo name collision** — use `Foundation.ProcessInfo` for system ProcessInfo
- **libproc constants** — `PROC_PIDPATHINFO_MAXSIZE` isn't bridged to Swift; hardcoded as 4096
- **Trunk-based development** — commit directly to `main`
