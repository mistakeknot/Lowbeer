# Architecture

## Component Diagram

```
LowbeerApp (@main, MenuBarExtra .window)
├── ProcessMonitor          — 3s poll, proc_pidinfo CPU deltas
├── ThrottleEngine          — Rule evaluation → SIGSTOP/SIGCONT
│   ├── RuleEvaluator       — Per-app + global threshold matching
│   ├── ScheduleEvaluator   — Time-of-day schedule matching
│   └── ThrottleSession     — Per-process state (full stop / duty-cycle)
├── ForegroundObserver      — NSWorkspace activation watcher
├── NotificationManager     — UNUserNotificationCenter
├── LowbeerSettings         — UserDefaults + JSON file persistence
└── UI
    ├── PopoverView         — Process list with sparklines
    ├── ProcessRowView      — Icon, name, CPU%, sparkline, throttle button
    ├── SparklineView       — 60-sample Canvas line chart
    └── Settings (3 tabs)   — General, Rules, Allowlist
```

## Directory Structure

```
Lowbeer/
  Lowbeer.xcodeproj/          Xcode project (generated via xcodeproj gem)
  Lowbeer/
    App/
      LowbeerApp.swift         @main — MenuBarExtra + Settings scenes
      AppDelegate.swift         Notification setup, lifecycle
    Core/
      ProcessMonitor.swift      Polls processes, computes CPU % from deltas
      ProcessSnapshot.swift     Raw proc_pidinfo sampling + process enumeration
      ThrottleEngine.swift      Evaluates rules, manages ThrottleSessions
      ThrottleSession.swift     Per-process SIGSTOP/SIGCONT state machine
      ForegroundObserver.swift  NSWorkspace didActivateApplication watcher
      RuleEvaluator.swift       Matches processes → rules → actions
      ScheduleEvaluator.swift   Time-of-day / day-of-week schedule matching
      NotificationManager.swift UNUserNotificationCenter delivery
    Models/
      ProcessInfo.swift         Observable process model (pid, name, cpu%, history)
      ThrottleRule.swift        Per-app rule + ThrottleAction + ThrottleSchedule
      AppIdentity.swift         Bundle ID or path-based process identifier
      ProcessHistory.swift      Ring buffer of 60 CPU % samples
      LowbeerSettings.swift     Global settings singleton (UserDefaults + JSON)
    Views/
      MenuBar/
        PopoverView.swift       Main popover layout (header, list, throttled section)
        ProcessRowView.swift    Single process row with icon, sparkline, button
        SparklineView.swift     Canvas-based 60-sample CPU history chart
      Settings/
        SettingsView.swift      Tab container (General, Rules, Allowlist)
        GeneralSettingsView.swift  Threshold, interval, action, launch at login
        RulesSettingsView.swift    Per-app rule table + add sheet
        AllowlistView.swift        Built-in + custom never-throttle list
    Helpers/
      SafetyList.swift          Hardcoded never-throttle processes/paths
      ProcessIcon.swift         NSRunningApplication icon lookup with caching
    Info.plist                  LSUIElement=YES (menu bar only, no dock icon)
    Lowbeer.entitlements        Sandbox disabled
```

## Persistence

- **UserDefaults** — global settings (threshold, interval, action, launch at login, notifications)
- **JSON files in ~/Library/Application Support/Lowbeer/** — per-app rules (`lowbeer_rules.json`), user allowlist (`lowbeer_allowlist.json`)
- Settings auto-save on property change via `didSet`

## Adding New Source Files

1. Create the `.swift` file in the appropriate directory
2. Re-run the xcodeproj generator: `ruby /tmp/gen_xcodeproj.rb`
3. Or manually add the file reference in Xcode

## Future Work (Not in v1)

- Privileged helper for throttling other users' processes
- Real energy impact metrics (if Apple publishes a public API)
- Homebrew cask formula for distribution
- Sparkline performance optimization for large process counts
- App icon and About window
- Code signing + notarization
