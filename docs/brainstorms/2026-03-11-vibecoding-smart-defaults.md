# Vibecoding Smart Defaults — Brainstorm

**Date:** 2026-03-11
**Bead:** Lowbeer-j4w
**Context:** User insight — vibecoding happens in terminals (Ghostty, Warp, Terminal.app, etc.), not just in AI tool binaries. The throttle defaults must understand the terminal-as-host pattern.

---

## The Problem

Lowbeer ships with a global CPU threshold (80%) and no app-specific rules. A vibecoding user installs it, and:

1. Claude Code spawns node processes inside Ghostty that burn 100% CPU during builds
2. Lowbeer SIGSTOPs Ghostty itself (wrong target — freezes the terminal UI)
3. Or Lowbeer SIGSTOPs the node child (correct, but no rule says to treat AI tool children differently)
4. Or worse: the user is actively typing in Ghostty, but a background tab is burning CPU — Lowbeer should NOT freeze the foreground terminal

**The core tension:** Terminals are both UI (never freeze when foreground) and containers (their children may be throttle-worthy). AI tools like Claude Code (`claude` binary), Cursor, and Copilot are themselves processes that spike during inference/builds.

---

## Process Landscape for Vibecoding

### AI Tools (the brains)

| Tool | Process Name(s) | Bundle ID | Notes |
|------|----------------|-----------|-------|
| Claude Code | `claude`, `node` | — | CLI tool, runs as node child processes |
| Cursor | `Cursor`, `Cursor Helper (Renderer)` | `com.todesktop.cursor` | Electron app with many helpers |
| Copilot (VS Code) | `Code`, `Code Helper (Renderer)` | `com.microsoft.VSCode` | Extension-driven CPU |
| Windsurf | `Windsurf`, helper processes | `com.codeium.windsurf` | Codeium's fork of VS Code |
| Ollama | `ollama`, `ollama serve` | — | Local LLM serving |
| LM Studio | `LM Studio` | `com.lmstudio.app` | Electron + llama.cpp |

### Terminal Emulators (the hosts)

| Terminal | Process Name | Bundle ID | Notes |
|----------|-------------|-----------|-------|
| Ghostty | `ghostty` | `com.mitchellh.ghostty` | GPU-rendered, can spike on scrollback |
| Warp | `Warp` | `dev.warp.Warp-Stable` | AI-native terminal, Rust-based |
| iTerm2 | `iTerm2` | `com.googlecode.iterm2` | Mature, many features |
| Terminal.app | `Terminal` | `com.apple.Terminal` | System default |
| Kitty | `kitty` | `net.kovidgoyal.kitty` | GPU-rendered |
| Alacritty | `alacritty` | `org.alacritty` | GPU-rendered, minimal |

### Build Tools (the workers)

| Tool | Process Name(s) | Notes |
|------|----------------|-------|
| Node.js | `node` | Claude Code, many dev tools |
| Python | `python3`, `python` | ML/AI tools |
| Rust compiler | `rustc`, `cargo` | Warp, system builds |
| Swift compiler | `swiftc`, `swift-frontend` | Xcode builds |
| Go compiler | `go`, `compile` | Many tools |
| webpack/esbuild | `node` (child) | Bundlers |

---

## Design Decisions

### Decision 1: What ships as "built-in" vs what's a user rule?

**Option A: Hardcoded presets**
Built-in rules that are always active. User can't remove them, only override thresholds.

**Option B: Default rules (recommended)**
Pre-populated `ThrottleRule` entries in `LowbeerSettings.rules` on first launch. User can modify, disable, or delete. Feels like "we set up sensible defaults for you" not "we know better than you."

**Option C: Profile bundles**
Named profiles ("Vibecoding", "General", "Gaming") that swap entire rule sets. More complex, probably overkill for v1.

**Recommendation: Option B.** Default rules are flexible and transparent. The user sees exactly what Lowbeer is doing and can customize. First-launch experience seeds the rules list.

### Decision 2: How to handle terminals?

Terminals are special: they're UI when foreground but host CPU-heavy children when background.

**Key insight:** We already have `throttleInBackground: Bool` on `ThrottleRule`. For terminals, this should ALWAYS be true — never throttle a foreground terminal.

**But should we throttle the terminal process itself?**

- Ghostty/Kitty/Alacritty use GPU rendering — CPU spikes are usually brief (scrollback rendering)
- Warp has AI features that spike CPU
- Terminal.app is lightweight
- The real CPU hogs are the *children* of terminals (node, python, rustc, etc.)

**Recommendation:** Default terminal rules should use `notifyOnly` action with a high threshold (150%+). This alerts the user that a terminal is hot without freezing it. The child processes (node, python, etc.) get separate rules.

BUT — we should reconsider. The user said terminals ARE where vibecoding happens. Maybe the right move is:

**Recommendation (revised):** Terminals get `throttleInBackground: true` with a *higher* threshold (150%) and `dutyCycle` action (not full stop). This way a background terminal doing a big build gets slowed down but not frozen, preserving its ability to handle SIGCONT gracefully.

### Decision 3: What about terminal child processes?

Claude Code spawns `node` processes. Should Lowbeer detect that a `node` process is a child of Ghostty and apply terminal-child rules?

**Option A: Process tree awareness**
Walk the process tree, detect parent-child relationships. Complex, adds ongoing maintenance.

**Option B: Match by process name only (recommended)**
`node` is `node` regardless of parent. If it's burning CPU, throttle it. The user doesn't care if it's Claude Code's node or webpack's node — they want CPU back.

**Option C: Match by both name and command-line args**
Could check if `node` was invoked with `claude` in argv. Very fragile, command-line args change.

**Recommendation: Option B.** Process name matching is simple and correct for the 95% case. If a user needs to distinguish, they can write a path-based rule.

### Decision 4: How aggressive should defaults be?

**Conservative (ship this):**
- AI IDE helpers: 120% CPU, 60s sustained, `.throttleTo(0.5)` (duty-cycle to 50%)
- Terminals: 200% CPU, 30s sustained, background-only, `.notifyOnly`
- Build tools (node, python, rustc): 150% CPU, 45s sustained, `.throttleTo(0.5)`
- Local LLMs (Ollama, LM Studio): 300% CPU, 120s sustained, `.notifyOnly`

**Rationale for local LLM leniency:** If you started Ollama to run inference, you *want* it to use CPU. Just notify so the user knows it's happening. Full-stop would break inference.

### Decision 5: What does "vibecoding preset" mean for the global threshold?

The global threshold (currently 80%) catches everything not matched by a rule. For vibecoding:
- Should probably be HIGHER (e.g., 120%) because dev machines routinely run hot
- Or keep it at 80% and let per-app rules override

**Recommendation:** Keep global at 80%, let per-app rules override. This protects against truly runaway processes while giving known tools room.

---

## Implementation Sketch

### New: `DefaultProfiles.swift`

A static list of pre-built `ThrottleRule` entries grouped by category:

```swift
enum DefaultProfiles {
    static let terminalRules: [ThrottleRule] = [
        // Ghostty, Warp, iTerm2, Terminal.app, Kitty, Alacritty
    ]
    static let aiToolRules: [ThrottleRule] = [
        // Claude Code helpers (Cursor, Copilot, Windsurf)
    ]
    static let localLLMRules: [ThrottleRule] = [
        // Ollama, LM Studio
    ]
    static var allDefaults: [ThrottleRule] {
        terminalRules + aiToolRules + localLLMRules
    }
}
```

### Modified: `LowbeerSettings.swift`

On first launch (no saved rules file), seed `rules` from `DefaultProfiles.allDefaults`.

### UI indicator

Rules seeded by defaults should be visually distinguishable (e.g., a small badge or "Default" label) so users know which rules they created vs which shipped with Lowbeer.

---

## Open Questions

1. **Should we detect installed tools?** Instead of shipping rules for ALL tools, only create rules for tools actually installed on this Mac. Pro: less clutter. Con: tools installed after Lowbeer wouldn't get rules until the user adds them. Recommendation: ship all rules, disable the ones for non-installed tools, re-check periodically.

2. **Terminal tabs vs terminal process:** When a user has 5 Ghostty windows, throttling the `ghostty` process affects ALL windows. Is this acceptable? (Yes — SIGSTOP is per-process, and a background terminal is background for all its windows.)

3. **Electron app helper processes:** Cursor spawns `Cursor Helper (Renderer)`, `Cursor Helper (GPU)`, etc. Should we match on prefix? The existing `AppIdentity.matches` does exact match on path or bundle ID. May need wildcard or prefix matching for helper processes.

---

## What Success Looks Like

A new Lowbeer user who vibecodes with Claude Code in Ghostty:
1. Installs Lowbeer
2. Opens it — sees pre-configured rules for Ghostty, Claude Code, Node.js, etc.
3. Starts working — Claude Code's node processes spike to 200% CPU
4. After 45 seconds, Lowbeer duty-cycles them to 50%
5. Ghostty stays responsive because it's foreground
6. User switches to Slack — Ghostty (now background) gets monitored but not frozen
7. User switches back to Ghostty — throttle immediately releases

That's the vibecoding-first experience.
