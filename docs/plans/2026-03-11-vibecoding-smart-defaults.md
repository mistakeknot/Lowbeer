# Plan: Vibecoding Smart Defaults (v2 — post-review)

**Date:** 2026-03-11
**Bead:** Lowbeer-j4w
**PRD:** `docs/prds/2026-03-11-vibecoding-smart-defaults.md`
**Review findings incorporated from:** architecture, quality, correctness, user/product agents

---

## Module 1: ThrottleRule `isDefault` field with safe Codable migration

**Files:** `Lowbeer/Models/ThrottleRule.swift`

Add `var isDefault: Bool` to `ThrottleRule`. **Critical:** Swift's synthesized `Codable` does NOT fall back to property initializer defaults for missing JSON keys — it throws `DecodingError.keyNotFound`, which `loadJSON`'s `try?` swallows as `nil`, silently wiping all user rules.

Fix: write a custom `init(from decoder: Decoder)` that uses `decodeIfPresent` with a `false` fallback:

```swift
var isDefault: Bool

enum CodingKeys: String, CodingKey {
    case id, identity, cpuThreshold, sustainedSeconds, action, schedule, throttleInBackground, enabled, isDefault
}

init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    identity = try c.decode(AppIdentity.self, forKey: .identity)
    cpuThreshold = try c.decode(Double.self, forKey: .cpuThreshold)
    sustainedSeconds = try c.decode(Int.self, forKey: .sustainedSeconds)
    action = try c.decode(ThrottleAction.self, forKey: .action)
    schedule = try c.decodeIfPresent(ThrottleSchedule.self, forKey: .schedule)
    throttleInBackground = try c.decode(Bool.self, forKey: .throttleInBackground)
    enabled = try c.decode(Bool.self, forKey: .enabled)
    isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
}
```

Update the memberwise `init()` to include `isDefault: Bool = false`.

## Module 2: DefaultRules

**Files:** `Lowbeer/Models/DefaultRules.swift` (new file)

Static enum in `Models/` (not `Helpers/` — it produces domain model types, not utilities).

### Rule Categories

**Terminal emulators (6)** — Background-only, high threshold, duty-cycle:
- Ghostty (`com.mitchellh.ghostty`), Warp (`dev.warp.Warp-Stable`), iTerm2 (`com.googlecode.iterm2`), Terminal.app (`com.apple.Terminal`), Kitty (`net.kovidgoyal.kitty`), Alacritty (`alacritty` via executablePath — no reliable bundle ID from Homebrew installs)
- Threshold: 150% CPU, 30s sustained
- Action: `.throttleTo(0.5)`
- `throttleInBackground: true`

**AI IDE helpers (4)** — Background-only, moderate threshold, duty-cycle:
- Cursor (`com.todesktop.cursor`), VS Code (`com.microsoft.VSCode`), Windsurf (`com.codeium.windsurf`), Claude Code (`claude` via executablePath — CLI tool, no bundle ID)
- Threshold: 120% CPU, 60s sustained
- Action: `.throttleTo(0.5)`
- `throttleInBackground: true`
- Note: `throttleInBackground` has no practical effect for CLI processes (ForegroundObserver uses NSWorkspace which only tracks GUI apps). This is fine — CLI tools should always be eligible.

**Build tools (2)** — Catch the actual worker processes:
- Node.js (`node` via executablePath), Python (`python3` via executablePath)
- Threshold: 150% CPU, 45s sustained
- Action: `.throttleTo(0.5)`
- `throttleInBackground: false` (always eligible — these are child processes, never foreground)
- **Why these are essential:** Claude Code spawns `node` processes. Without a rule, `node` hits the global 80% threshold and gets full SIGSTOP after 30s — the wrong behavior. The explicit rule gives it a higher threshold and duty-cycle instead of full stop.

**Local LLMs (2)** — Very high threshold, notify-only:
- Ollama (`ollama` via executablePath), LM Studio (`com.lmstudio.app`)
- Threshold: 300% CPU, 120s sustained
- Action: `.notifyOnly`
- `throttleInBackground: false`

**Total: 14 default rules.** All marked `isDefault: true`, `enabled: true`.

### Identity strategy (from architecture review)

- **GUI apps:** Use `bundleIdentifier` (covers all helper processes — Electron helpers share parent's bundle ID)
- **CLI tools (claude, node, python3, ollama, alacritty):** Use `executablePath` with the binary name (matches via existing `path.hasSuffix("/\(ep)")` logic)
- **No `namePrefix` field needed.** The original plan's `namePrefix` is dropped — BSD process names are truncated to 15 chars by the kernel, making prefix matching unreliable. Bundle ID and path suffix cover all targets.

## Module 3: First-launch seeding in LowbeerSettings

**Files:** `Lowbeer/Models/LowbeerSettings.swift`

Use a dedicated `hasSeededDefaults` UserDefaults flag — NOT an empty-array check (which can't distinguish first launch from "user deleted all rules"):

```swift
// In private init(), after loading rules:
if !defaults.bool(forKey: "hasSeededDefaults") {
    if rules.isEmpty {
        rules = DefaultRules.all
    }
    defaults.set(true, forKey: "hasSeededDefaults")
}
```

This seeds exactly once. A user who deletes all rules will not get re-seeded.

## Module 4: Rule ordering — custom before defaults

**Files:** `Lowbeer/Models/LowbeerSettings.swift`

`RuleEvaluator` uses first-match semantics. User-created rules must precede default rules to allow overrides. Add a stable sort after loading:

```swift
// After loading/seeding rules, ensure custom rules precede defaults
rules.sort { !$0.isDefault && $1.isDefault }
```

This is a stable sort — among custom rules (and among defaults), the existing order is preserved. Only the custom-before-default invariant is enforced.

Also apply this sort in `saveRules()` before writing, so the file on disk always has the correct order.

## Module 5: Fix notifyOnly deduplication (existing bug, worsened by LLM rules)

**Files:** `Lowbeer/Core/ThrottleEngine.swift`

The existing code removes `.notifyOnly` sessions immediately after creation, causing re-notification every poll cycle (every 3s) for sustained high-CPU processes like Ollama. With the new LLM rules, this would produce ~200 notifications in 10 minutes.

Fix: track notifyOnly sessions like real sessions. They should persist until CPU drops below threshold, preventing re-triggering. Remove the block at lines 160-168 that strips the session. The dedup already works for `.stop` and `.throttleTo` sessions — just stop special-casing `.notifyOnly`.

Also fix the double-notification: lines 150-158 send a notification, then lines 160-167 send another one for the same action.

## Module 6: Tests

**Files:** `LowbeerTests/Models/DefaultRulesTests.swift` (new), update existing test files

### DefaultRulesTests:
- All 14 rules have `isDefault: true` and `enabled: true`
- Terminal rules have `throttleInBackground: true`
- LLM rules have `.notifyOnly` action
- Build tool rules have `.throttleTo(0.5)` action
- No duplicate identities across all rules
- Each rule has either a non-empty `bundleIdentifier` or non-empty `executablePath`

### ThrottleRuleCodableTests (update):
- Round-trip encode/decode with `isDefault: true` preserves the field
- **Migration test:** Decode a JSON string WITHOUT the `isDefault` key → field defaults to `false`

### RuleEvaluatorTests (update):
- A process matching a default rule at 100% CPU (below 120% threshold) does NOT fall through to the global 80% threshold
- Rule ordering: custom rule at threshold X takes precedence over default rule at threshold Y for the same identity

### LowbeerSettingsTests (update):
- First launch (no file, no flag) seeds defaults
- Second launch (file exists, flag set) preserves existing rules
- User with empty rules and `hasSeededDefaults: true` stays empty

## Execution Order

1. Module 1 (ThrottleRule isDefault) — no dependencies
2. Module 2 (DefaultRules) — depends on 1
3. Module 3 (Settings seeding) — depends on 2
4. Module 4 (Rule ordering) — depends on 1
5. Module 5 (notifyOnly fix) — independent
6. Module 6 (Tests) — depends on all

Modules 1 and 5 can be done in parallel.

## Xcodeproj

After adding `DefaultRules.swift` and `DefaultRulesTests.swift`, regenerate the Xcode project. Locate the generation script first:

```bash
find /tmp -name "gen_xcodeproj.rb" 2>/dev/null || find . -name "gen_xcodeproj*" 2>/dev/null
```

## Review Findings NOT Addressed (deferred)

- **`isDefault` UI badge** — Important for trust but requires UI work beyond this bead's scope. File as companion bead.
- **Multi-Space foreground detection edge case** — Pre-existing, not worsened by this change.
- **Warp beta/nightly bundle IDs** — Document as known limitation.
- **SafetyList allowlist stays exact-match only** — Correct as-is, no change needed.
