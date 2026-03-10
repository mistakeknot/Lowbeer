# Lowbeer Conventions

## Code Style

- **Swift 5.9** with SwiftUI lifecycle
- **@Observable** macro (not ObservableObject/Combine)
- Use `Foundation.ProcessInfo` when referring to the system's ProcessInfo (to avoid collision with our own `ProcessInfo`)
- Hardcode `PROC_PIDPATHINFO_MAXSIZE` as `4096` (not bridged to Swift)
- No force unwraps except in clearly safe contexts (e.g., static data)

## File Organization

```
Lowbeer/
  App/        — Entry point, AppDelegate, MenuBarExtra
  Core/       — Business logic (monitoring, throttling, scheduling)
  Models/     — Data types, settings, rules
  Views/      — SwiftUI views (MenuBar/, Settings/)
  Helpers/    — Utilities (SafetyList, ProcessIcon, window controllers)
```

## Naming

- **Files** — PascalCase matching the primary type they contain
- **Types** — PascalCase (e.g., `ThrottleEngine`, `ProcessSnapshot`)
- **Functions/properties** — camelCase
- **Constants** — camelCase or UPPER_SNAKE for C-bridged values

## Safety Rules

- Never send SIGSTOP without first verifying the PID still belongs to the expected process
- Never throttle processes on the safety list (SafetyList.swift)
- Always resume all throttled processes on app quit (AppDelegate cleanup)
- Verify foreground status before throttling — auto-resume foreground apps

## Build System

- Xcode project generated via `xcodeproj` Ruby gem (`ruby /tmp/gen_xcodeproj.rb`)
- Not using Swift Package Manager
- Minimum deployment: macOS 14 (Sonoma)
- Unsandboxed (required for SIGSTOP/SIGCONT)

## Git

- Trunk-based development — commit directly to `main`
- No feature branches unless explicitly requested
- Conventional-style commit messages (e.g., "add duty-cycle throttling", "fix PID reuse detection")

## Testing

- Manual testing via `yes > /dev/null &` to create CPU load
- Verify throttle detection, foreground resume, settings persistence
- No automated test suite yet (v1 goal)
