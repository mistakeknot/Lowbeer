# Lowbeer — Vision

**Last updated:** 2026-03-09
**Philosophy:** [`PHILOSOPHY.md`](../PHILOSOPHY.md)
**Brainstorm:** [`docs/brainstorms/2026-03-06-lowbeer-initial-goals.md`](brainstorms/2026-03-06-lowbeer-initial-goals.md)
**Research:** [`docs/research/apple-silicon-throttling.md`](research/apple-silicon-throttling.md)

---

## The Big Idea

You're vibecoding on your MacBook Pro — Claude Code is spinning up subprocesses, Cursor has three language servers running, Ollama is doing local inference in the background. Your fans ramp, your battery drains from 80% to 30% in an hour, and your machine turns into a space heater. macOS doesn't manage this. App Tamer costs $15 and is closed-source.

Lowbeer is the app every Apple Silicon MacBook owner downloads to maximize battery life. It monitors every process in real time and automatically throttles the ones burning through your battery — whether that's a runaway `node` process, a Claude Code subprocess that finished but didn't exit, or Copilot's language server indexing your entire monorepo. Named after Ainsley Lowbeer from Gibson's *The Peripheral*, it dampens and corrects without overreach.

## Target Audience

**Primary:** Vibecoding and AI-heavy Mac users — people running Claude Code, Cursor, Copilot, Windsurf, local LLMs via Ollama or LM Studio. These tools spawn aggressive background processes that traditional throttlers don't understand.

**Secondary:** Any MacBook user who wants longer battery life without babysitting Activity Monitor.

## Design Principles

1. **Do No Harm** — Never throttle a process that could destabilize the system. The safety list is non-negotiable; one wrong SIGSTOP can freeze a desktop.

2. **Transparent by Default** — Every throttle action is visible and instantly reversible. Show users what Lowbeer is doing and how much battery it's saving.

3. **Zero Configuration Works** — Sensible defaults cover 90% of use cases. Ship with smart presets for known AI tools (Claude Code, Cursor, Copilot, Ollama). Power users can customize, but the app should work out of the box.

4. **Show Your Value** — Daily battery savings counter in the menu bar. Process offender leaderboard in the popover ("Claude Code used 45% of your CPU this week"). Users should feel the value every time they glance at their menu bar.

5. **Native and Minimal** — A SwiftUI menu bar app using system APIs directly. No Electron, no frameworks, negligible resource usage. Lowbeer should never become the problem it solves.

6. **Open Source First** — MIT license, public repo, community contributions welcome. For a tool this close to the OS, users want to inspect the code.

## Current State

- **Version:** v0.1.0 (first public release)
- **Maturity:** Core functionality complete — monitoring, throttling, duty-cycle, rules, settings, notifications
- **Architecture:** 26 Swift files across 5 modules (App, Core, Models, Views, Helpers)
- **Platform:** macOS 14+ (Sonoma), unsandboxed, Swift 5.9 with SwiftUI
- **Distribution:** DMG via GitHub Releases (ad-hoc signed); automated CI release workflow
- **Repo:** [github.com/mistakeknot/Lowbeer](https://github.com/mistakeknot/Lowbeer)

**Key milestones achieved:**
- CPU monitoring via proc_pidinfo with delta calculation
- SIGSTOP/SIGCONT throttling with duty-cycle support
- Per-app rules with custom thresholds and actions
- Foreground detection with auto-resume
- Time-based scheduling
- Safety list protecting system processes
- Release pipeline (scripts/package.sh + GitHub Actions)

## Where We're Going

### Near-term: Ship v1.0 with vibecoding defaults (next 2-4 weeks)
Polish what exists and get it into vibecoding users' hands. Ship smart presets for Claude Code, Cursor, Copilot, and Ollama processes. Add battery savings counter to the menu bar. Harden PID reuse safety (start-time verification). Add automated tests. Homebrew cask for easy install.

### Medium-term: Intelligent throttling (1-3 months)
Move beyond binary SIGSTOP/SIGCONT. Research Apple Silicon-native throttling — QoS class demotion to pin processes to efficiency cores instead of fully freezing them, `setpriority()`/nice for gentler slowdowns. Add process offender leaderboard showing which AI tools drain the most battery over time. Sparkle auto-updates. Energy impact approximation via CPU + IO.

### Long-term: The battery life app for Mac (3-6 months)
Become the definitive tool every MacBook owner installs. Apple Silicon-optimized throttling that slows processes down rather than freezing them. Community-contributed profiles for AI tools. "Lowbeer saved you 2.3 hours of battery today" as social proof that drives word-of-mouth. Privileged helper for root process throttling.

## What We Believe

These are the bets Lowbeer makes. If any prove wrong, the direction changes.

1. **Vibecoding is the killer use case.** AI development tools (Claude Code, Cursor, Copilot, Ollama, LM Studio) are the worst battery offenders on modern Macs. They spawn many background processes, they're CPU-hungry, and their users are technical enough to install a menu bar app but busy enough to want it automated.

2. **SIGSTOP/SIGCONT is the right v1 mechanism, but not the endgame.** It works today without entitlements or kernel extensions. But on Apple Silicon, the real opportunity is QoS demotion — pinning runaway processes to efficiency cores instead of freezing them. "Slow down" is better UX than "freeze." SIGSTOP remains the fallback for processes that need to be fully stopped.

3. **Battery savings must be visible.** Users need to feel the value. "Lowbeer saved you 2.3 hours of battery today" is more compelling than a silent menu bar icon. The savings counter and offender leaderboard turn Lowbeer from invisible utility into something users recommend to friends.

4. **CPU percentage is a good-enough energy proxy for v1.** There's no public API for per-process energy impact. CPU% plus IO activity covers the cases users care about. As we learn more about Apple Silicon power characteristics, we can improve the model.

5. **Smart defaults beat configuration.** Shipping with profiles for known AI tools ("Claude Code: throttle to 25% when in background") is worth more than a flexible rule editor. Know the user's tools before they have to tell you.

6. **Open source wins in utilities.** The $15 App Tamer market proves demand; open source proves trustworthiness. For a tool that sends SIGSTOP to your processes, inspectability matters.
