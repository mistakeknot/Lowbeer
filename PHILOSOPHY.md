# Lowbeer Philosophy

## Core Principle

**The user's computer belongs to the user.** Runaway processes that waste CPU, drain battery, and spin fans are a failure of the operating system to protect the user. Lowbeer fills that gap — it's the systemic governor that dampens and corrects.

## Design Principles

### 1. Do No Harm
Never throttle a process that could destabilize the system. The safety list exists because one wrong SIGSTOP can freeze a desktop. When in doubt, don't throttle.

### 2. Transparent by Default
Every throttle action should be visible and reversible. Users must understand what Lowbeer is doing and be able to override it instantly. No silent, hidden behavior.

### 3. Zero Configuration Works
Out of the box, Lowbeer should work well with sensible defaults (80% threshold, 30s sustained). Power users can customize, but the defaults should cover 90% of cases.

### 4. Native and Minimal
A menu bar app, not an Electron app. Use system APIs directly (libproc, SIGSTOP/SIGCONT). No frameworks, no dependencies, no bloat. Lowbeer should use negligible resources itself.

### 5. Open Source First
App Tamer costs $15 and is closed-source. Lowbeer exists because this functionality should be free and inspectable. MIT license, public repo, community contributions welcome.

## Non-Goals

- **Not a task manager.** Activity Monitor already exists. Lowbeer shows processes only to explain what it's throttling and why.
- **Not a system optimizer.** Lowbeer doesn't clean memory, manage startup items, or tune kernel parameters.
- **Not cross-platform.** macOS-specific by design. SIGSTOP/SIGCONT and libproc are the right tools for this platform.
