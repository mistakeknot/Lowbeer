# PRD: Vibecoding Smart Defaults

**Date:** 2026-03-11
**Bead:** Lowbeer-j4w
**Priority:** P1
**Parent Epic:** Lowbeer-flw (v1.0 public release)

---

## Problem Statement

Lowbeer ships with a single global CPU threshold (80%) and no app-specific rules. Vibecoding users — the primary target audience — must manually configure rules for every AI tool and terminal they use. Without defaults, Lowbeer either throttles the wrong things (foreground terminals) or misses the right things (background build processes). This makes the out-of-box experience poor and contradicts the "built for vibecoding" positioning.

## User Stories

1. **As a vibecoding developer**, I want Lowbeer to know about Claude Code, Cursor, and Ghostty out of the box, so I don't have to configure rules manually.
2. **As a terminal user**, I want my foreground terminal to never freeze, even if background terminals get throttled.
3. **As an Ollama user**, I want Lowbeer to notify me when inference is heavy but not kill my model mid-generation.
4. **As a new Lowbeer user**, I want to see which rules are built-in defaults vs ones I created, so I understand what Lowbeer is doing.

## Solution

### 1. Default Rule Profiles (`DefaultProfiles.swift`)

A new file defining pre-built `ThrottleRule` entries for three categories:

**Terminal Emulators** — High threshold, background-only, duty-cycle (not full stop):
- Ghostty, Warp, iTerm2, Terminal.app, Kitty, Alacritty
- Threshold: 150% CPU, 30s sustained
- Action: `.throttleTo(0.5)` (duty-cycle to 50%)
- `throttleInBackground: true` (never throttle foreground terminal)

**AI IDE Helpers** — Moderate threshold, background-only, duty-cycle:
- Cursor (+ Cursor Helper *), Copilot/VS Code (+ Code Helper *), Windsurf
- Threshold: 120% CPU, 60s sustained
- Action: `.throttleTo(0.5)`
- `throttleInBackground: true`

**Local LLMs** — Very high threshold, notify-only:
- Ollama, LM Studio
- Threshold: 300% CPU, 120s sustained
- Action: `.notifyOnly`
- Rationale: User intentionally runs these; stopping them breaks inference

### 2. First-Launch Seeding

On first launch (no existing `lowbeer_rules.json`), `LowbeerSettings` seeds `rules` from `DefaultProfiles.allDefaults`. Subsequent launches load from the saved file as today.

### 3. Default Rule Marking

Add an `isDefault: Bool` field to `ThrottleRule`. Default rules are visually distinguishable in the settings UI (future work — not in this bead). This field is `false` for user-created rules.

### 4. AppIdentity Enhancement for Helpers

Electron apps spawn helper processes with predictable name prefixes (e.g., "Cursor Helper (Renderer)"). Add a `namePrefix: String?` field to `AppIdentity` and update `matches()` to support prefix matching. This covers `Cursor Helper *`, `Code Helper *`, etc.

## Non-Goals

- Process tree walking (detecting parent-child relationships)
- Auto-detecting installed tools (ship all rules, user disables unneeded ones)
- Profile switching UI (single rule set is sufficient for v1)
- Build tool rules (node, python, rustc) — these are caught by the global threshold

## Success Criteria

1. New Lowbeer install shows pre-populated rules for 6 terminals + 4 AI tools + 2 local LLMs
2. Foreground terminal is never throttled
3. Background terminal with sustained CPU gets duty-cycled (not frozen)
4. Ollama running inference triggers notification but is not stopped
5. All default rules are editable and deletable by the user

## Technical Risks

- **Helper process prefix matching:** Changing `AppIdentity.matches()` affects all rule evaluation. Must maintain backward compatibility with existing exact-match rules.
- **ThrottleRule schema change:** Adding `isDefault` and `namePrefix` changes the Codable schema. Must handle migration from existing saved rules (missing fields default to `false`/`nil`).
