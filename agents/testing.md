# Testing

No automated test suite yet — the app requires live process monitoring and signal delivery. All testing is manual.

## Runaway Process Detection

```bash
# Create a 100% CPU process
yes > /dev/null &
YES_PID=$!

# Lowbeer should detect it in the popover within one poll cycle (3s)
# After the sustained duration (default: 30s), it should be throttled

# Verify it's stopped
ps -o state= -p $YES_PID  # Should show 'T' (stopped)

# Resume via Lowbeer UI, verify it runs again
ps -o state= -p $YES_PID  # Should show 'R' or 'S'

# Clean up
kill $YES_PID
```

## Foreground Auto-Resume

1. Create a per-app rule for an app (e.g., Terminal) with a low threshold
2. Generate CPU load in that app so it triggers throttling
3. Verify the app gets throttled when in background (check popover)
4. Switch to the app — should auto-resume immediately
5. Switch away — should re-evaluate and potentially re-throttle

## Per-App Rules

1. Open Settings → Rules → Add
2. Pick a running app, set threshold to something low (e.g., 5%)
3. Generate CPU load in that app
4. Verify rule-specific action is applied (not the global default)
5. Disable the rule — verify global threshold applies instead

## Schedule Rules

1. Create a rule with a schedule (e.g., active only Mon-Fri 09:00-17:00)
2. Verify the rule fires during the window
3. Change system clock or wait — verify the rule deactivates outside the window
4. Test `invertSchedule: true` — rule should be active OUTSIDE the window

## Settings Persistence

1. Change several settings (threshold, rules, allowlist entries)
2. Quit Lowbeer
3. Relaunch — verify all settings persisted
4. Check files exist:
   - `~/Library/Application Support/Lowbeer/lowbeer_rules.json`
   - `~/Library/Application Support/Lowbeer/lowbeer_allowlist.json`

## Allowlist

1. Add a process to Settings → Allowlist
2. Generate CPU load for that process
3. Verify it is never throttled regardless of CPU usage
4. Remove from allowlist — verify it can be throttled again

## Edge Cases

- **Quit while processes are throttled** — all should resume (SIGCONT sent)
- **Throttled process exits naturally** — session should be cleaned up on next poll
- **PID reuse** — stop a throttled process, wait for PID reuse, verify Lowbeer doesn't SIGSTOP the new process
- **Very short poll interval (1s)** — verify sustained duration still works correctly
