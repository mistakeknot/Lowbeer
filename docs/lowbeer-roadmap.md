# Lowbeer — Roadmap

**Last updated:** 2026-03-09
**PRD:** [`docs/PRD.md`](PRD.md)
**Vision:** [`docs/lowbeer-vision.md`](lowbeer-vision.md)
**Research:** [`docs/research/apple-silicon-throttling.md`](research/apple-silicon-throttling.md)

---

## Phase 1: v1.0 — Vibecoding Battery Saver (current)

Ship the app every MacBook vibecoder downloads to save battery. Smart defaults for AI tools, visible battery savings, hardened safety.

**Epic:** `Lowbeer-flw`

| Item | Bead | Priority | Status |
|------|------|----------|--------|
| PID start-time verification for reuse safety | `Lowbeer-hht` | P1 | Planned |
| Automated test suite (models + throttle engine) | `Lowbeer-p5i` | P1 | Planned |
| Menu bar polish and system CPU display | `Lowbeer-4qe` | P1 | Planned |
| Vibecoding smart defaults (Claude Code, Cursor, Copilot, Ollama, Windsurf, LM Studio) | `Lowbeer-j4w` | P1 | Planned |
| Battery savings counter in menu bar | `Lowbeer-squ` | P1 | Planned |
| Process offender leaderboard in popover | `Lowbeer-dni` | P1 | Planned |
| Zombie process filtering (skip state=Z) | `Lowbeer-tvg` | P1 | Planned |
| Launch-at-login verification (SMAppService) | `Lowbeer-m7c` | P1 | Planned |
| SIGSTOP debounce for rapid PID events | `Lowbeer-wjn` | P1 | Planned |

**Exit criteria:** Vibecoding users can install via DMG, get smart defaults for their AI tools, and see "Lowbeer saved you X hours today" in the menu bar. Automated tests passing, no known safety bugs.

## Phase 1.5: Distribution

Make Lowbeer easy to install and keep updated.

| Item | Bead | Priority | Status |
|------|------|----------|--------|
| Homebrew cask formula | `Lowbeer-sxg` | P2 | Planned |
| Sparkle auto-update integration | `Lowbeer-aow` | P2 | Planned |

**Exit criteria:** `brew install --cask lowbeer` works, auto-update delivers patches.

## Phase 2: Apple Silicon Intelligent Throttling

Move beyond SIGSTOP. Use Apple Silicon's E-core/P-core architecture to throttle smarter — slow processes down instead of freezing them.

**Epic:** `Lowbeer-9xw`

| Item | Bead | Priority | Status |
|------|------|----------|--------|
| E-core demotion via `taskpolicy -b` | `Lowbeer-un8` | P2 | Planned |
| Thermal-aware throttle aggressiveness | `Lowbeer-3xz` | P2 | Planned |
| Hybrid throttle strategy (E-core + duty-cycle) | `Lowbeer-4uc` | P2 | Blocked by `Lowbeer-un8` |
| Energy impact estimation (CPU + IO model) | `Lowbeer-skf` | P2 | Planned |

**Three-tier throttle strategy:**
1. **E-core demotion** (`taskpolicy -b`) — process keeps running at ~1/3 power
2. **Duty-cycle** (SIGSTOP/SIGCONT on E-cores) — limit to N% CPU
3. **Full stop** (SIGSTOP) — 0% CPU

**Exit criteria:** Default throttle action is E-core demotion. SIGSTOP reserved for aggressive mode. Thermal state drives automatic escalation.

## Phase 3: The Battery Life App for Mac

Become the definitive tool every MacBook owner installs.

**Epic:** `Lowbeer-ho0`

| Item | Bead | Priority | Status |
|------|------|----------|--------|
| Community-contributed AI tool profiles | `Lowbeer-9a7` | P3 | Planned |
| IOReport power telemetry (experimental) | `Lowbeer-w7f` | P3 | Planned |
| Privileged helper for root process throttling | `Lowbeer-1nt` | P3 | Planned |
| Coalition-aware throttling | `Lowbeer-4n7` | P3 | Planned |

**Exit criteria:** Real watts-saved display, community profile repository, root process throttling opt-in.

---

## Completed

| Item | Bead | Phase |
|------|------|-------|
| Core CPU monitoring via proc_pidinfo | — | Pre-v1 |
| SIGSTOP/SIGCONT throttling with duty-cycle | — | Pre-v1 |
| Per-app rules with custom thresholds | — | Pre-v1 |
| Foreground detection with auto-resume | — | Pre-v1 |
| Time-based scheduling | — | Pre-v1 |
| Safety list protecting system processes | — | Pre-v1 |
| Settings persistence (UserDefaults + JSON) | — | Pre-v1 |
| Menu bar UI with sparkline charts | — | Pre-v1 |
| GitHub remote + initial push | — | Phase 1 |
| DMG packaging + release workflow | `Lowbeer-7lv` | Phase 1 |
