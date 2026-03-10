# Lowbeer Philosophy

## Core Principle

**Your MacBook's battery belongs to you, not to runaway background processes.** AI coding tools — Claude Code, Cursor, Copilot, Ollama — spawn aggressive subprocesses that burn through battery while you're focused on building. macOS doesn't manage this. Lowbeer fills that gap — it's the systemic governor that dampens and corrects.

## Design Principles

### 1. Do No Harm
Never throttle a process that could destabilize the system. The safety list exists because one wrong SIGSTOP can freeze a desktop. When in doubt, don't throttle.

### 2. Transparent by Default
Every throttle action should be visible and reversible. Users must understand what Lowbeer is doing and be able to override it instantly. No silent, hidden behavior.

### 3. Show Your Value
Users need to feel the impact. A battery savings counter ("Saved 2.3h today") and a process offender leaderboard ("Claude Code: 45% of CPU this week") turn Lowbeer from an invisible utility into something users recommend to friends.

### 4. Zero Configuration Works
Out of the box, Lowbeer should work well with sensible defaults (80% threshold, 30s sustained) and smart presets for known AI tools. Power users can customize, but the defaults should cover 90% of cases.

### 5. Native and Minimal
A menu bar app, not an Electron app. Use system APIs directly (libproc, SIGSTOP/SIGCONT, taskpolicy). No frameworks, no dependencies, no bloat. Lowbeer should use negligible resources itself.

### 6. Open Source First
App Tamer costs $15 and is closed-source. Lowbeer exists because this functionality should be free and inspectable. For a tool that sends SIGSTOP to your processes, inspectability matters. MIT license, public repo, community contributions welcome.

## Non-Goals

- **Not a task manager.** Activity Monitor already exists. Lowbeer shows processes only to explain what it's throttling and why.
- **Not a system optimizer.** Lowbeer doesn't clean memory, manage startup items, or tune kernel parameters.
- **Not cross-platform.** macOS-specific by design. SIGSTOP/SIGCONT, taskpolicy, and libproc are the right tools for this platform.
- **Not a dashboard.** The offender leaderboard shows value, but users should not need to interact with Lowbeer daily. It's set-and-forget with visible proof of impact.
