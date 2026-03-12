# Battery Detective — Brainstorm

**Date:** 2026-03-11
**Bead:** Lowbeer-waw (epic), Lowbeer-2lf (research)
**User problem:** "My laptop is using a ton of battery for no good reason and I can't figure out why or how to fix it"

---

## The Problem

Lowbeer currently throttles runaway processes reactively but gives the user no visibility into *why* their battery is dying. The existing beads (Lowbeer-dni offender leaderboard, Lowbeer-squ battery savings counter, Lowbeer-skf energy estimation) were planned as separate features. The user's actual need is a single integrated experience that answers: **"Why is my battery dying, and what can I do about it?"**

## Desired Experience

Three layers, working together:

### Layer 1: Menu Bar Energy Indicator
Glanceable — a number or color in the menu bar showing current system power draw.
- e.g., `⚡ 4.2W` or a color-coded dot (green/yellow/red)
- Tells you at a glance: "something is wrong" vs "everything is normal"
- Updates every few seconds

### Layer 2: Smart Battery Drain Notification
Proactive — fires when drain is abnormal without the user having to look.
- "Your battery is draining 3x faster than usual. Top culprit: node (Claude Code) at 180% CPU for 12 minutes."
- Action buttons: [Throttle It] [Dismiss]
- Only fires when something genuinely unusual is happening (not just "you're compiling")

### Layer 3: Battery Detective View (popover)
The full diagnostic — clicking the menu bar icon opens a "why is my battery dying?" view.
- Top energy offenders ranked by estimated Wh consumed
- How long each has been burning CPU
- What Lowbeer did about each (throttled/notified/nothing)
- One-click "fix it" actions per process
- Daily battery savings estimate

---

## Energy Measurement Research

### Approach 1: IOReport (Apple Silicon hardware counters)

**What it is:** Private IOKit API that reads per-CPU-cluster power telemetry from Apple Silicon's Closed Loop Performance Controller (CLPC). Same data source as `powermetrics`.

**Key facts:**
- Returns per-subsystem energy: CPU P-cluster, CPU E-cluster, GPU, ANE, DRAM
- **No root required** for unsandboxed apps
- Per-cluster granularity (not per-process)
- Well-proven: used by socpowerbud (Obj-C), macmon (Rust), NeoAsitop (Swift)
- Private/undocumented API — risk of breakage across macOS versions

**Reference implementations:**
- [socpowerbud](https://github.com/dehydratedpotato/socpowerbud) — Obj-C, sudoless
- [NeoAsitop](https://github.com/op06072/NeoAsitop) — Swift, sudoless
- [macmon](https://github.com/vladkens/macmon) — Rust
- [freedomtan/test-ioreport](https://github.com/freedomtan/test-ioreport) — reference C implementation

**How it works:**
1. Subscribe to IOReport channels (Energy Model group)
2. Take two samples with `IOReportCreateSamples` / `IOReportCreateSamplesDelta`
3. Parse returned CFDictionary for energy values (mJ/µJ)
4. Convert to watts: P = E / t

### Approach 2: IOPSCopyPowerSourcesInfo (battery discharge rate)

**What it is:** Public IOKit API returning battery state — capacity, voltage, current.

**Key facts:**
- Public API, stable across versions
- Returns voltage and current → instantaneous power: P = V × I
- **Only works on battery** (useless on AC power)
- Low temporal resolution (~1 Hz, limited by battery firmware)
- System-level only — cannot attribute to individual processes
- Good for detecting "abnormal drain" by comparing against historical baseline

### Approach 3: CPU% × Power Coefficient (proxy)

**What it is:** Estimate per-process energy by multiplying CPU% by a power coefficient.

**Key facts:**
- Already have CPU% from ProcessMonitor
- Accuracy is poor (5-10× error) due to P-core vs E-core power difference (~10×) and DVFS
- No additional API needed
- Activity Monitor's "Energy Impact" is essentially this — widely criticized for inaccuracy
- Works as relative ranking even if absolute values are wrong

**Apple Silicon power data (from teardowns/measurements):**
| Chip | P-core max | E-core max | Full CPU load |
|------|-----------|-----------|---------------|
| M1 | ~1000 mW | ~100 mW | ~9 W (8P+2E) |
| M3 | ~1000 mW | ~100 mW | ~7 W (6P+6E) |

### Approach 4: proc_pidinfo CLPC (per-thread energy) — Not viable

Per-thread CLPC energy counters exist via `PROC_PIDTHREADCOUNTS`, but only for the calling process's own threads. Cannot measure other processes. Not useful for Lowbeer.

---

## Recommended Architecture: Hybrid Model

### System-level truth: IOReport
IOReport gives us the actual system power draw. This powers:
- Menu bar wattage display
- "Abnormal drain" detection (compare current draw vs historical baseline)
- Accuracy credibility — we show real watts, not estimates

### Per-process ranking: CPU% proxy (improved)
CPU% is the only available per-process signal. We improve it by:
- Weighting by core type if we can determine P-core vs E-core scheduling (IOReport tells us per-cluster load, which we can correlate with process CPU%)
- Using it as a **relative ranking** (not absolute energy), which is actually accurate enough

### Battery context: IOPSCopyPowerSourcesInfo
When on battery, we can show:
- Remaining battery time at current draw rate
- "You've used X% battery in the last hour, normally it's Y%"
- This adds urgency context but not diagnostic precision

### The combination
```
IOReport (system Watts)  →  "Your Mac is drawing 12W right now"
CPU% per-process         →  "node is responsible for ~60% of that"
IOPSCopyPowerSourcesInfo →  "At this rate, battery dies in 2.1 hours"
```

This gives the user: (1) accurate system-level power, (2) actionable per-process ranking, (3) battery impact context.

---

## Why This Matters for Lowbeer's Identity

Every other macOS "battery" app (coconutBattery, iStatMenus, AlDente) shows battery health and charge cycles. None of them answer "why is my battery dying right now and what can I do?"

Lowbeer already has the throttle engine. Adding energy measurement turns it from "a process throttler" into "the app that saves your battery and tells you why it was dying." That's a much stronger product story, especially for the vibecoding audience where background AI builds routinely drain battery 3-5× faster than normal.

---

## Open Questions

1. **IOReport API stability:** Private API could break on macOS 15. Mitigation: graceful fallback to CPU% proxy. NeoAsitop and macmon both work on macOS 14 — should be stable for a while.

2. **IOReport overhead:** How much does frequent sampling cost? socpowerbud samples at 1s intervals. We should benchmark at 3s (our existing poll interval) to see if there's measurable overhead.

3. **Historical baseline:** To detect "abnormal drain," we need a baseline. Options: (a) rolling average over 24 hours, (b) per-activity-type baseline (e.g., "during coding sessions your Mac usually draws 5W"), (c) simple percentile thresholds. Start with a rolling average.

4. **UI design for the detective view:** The popover is currently a simple process list. The battery detective needs a richer layout (power breakdown, timeline, actions). Should this be a separate window or an expanded popover? The popover has space constraints (WindowGroup .menuBarExtra with .window style). A separate panel might be needed.
