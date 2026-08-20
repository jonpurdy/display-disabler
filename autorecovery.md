# Auto-Recovery Notes

This note captures the experimental work around automatically restoring the built-in display after the external display is unplugged.

## Goal

Desired flow:

- Disable the built-in MacBook display while an external monitor is connected.
- Unplug the external monitor later.
- Automatically re-enable the built-in display.

## What worked

- Disabling a display using the private CGS configuration path worked reliably.
- Manual re-enable from the app also worked reliably.
- The disabled display disappeared from System Settings > Displays, which strongly suggests the app was changing real display layout state rather than dimming brightness.

The successful manual path was:

- `CGBeginDisplayConfiguration`
- optional `CGConfigureDisplayMirrorOfDisplay(..., kCGNullDirectDisplay)`
- `CGSConfigureDisplayEnabled(config, displayID, false/true)`
- `CGCompleteDisplayConfiguration(config, .permanently)`

## What was tried for auto-recovery

Several callback-driven recovery strategies were explored:

1. Re-enable the built-in display when no external display was active.
2. Re-enable the built-in display when no external display was reported online.
3. Remember the specific built-in display that had been disabled and only recover that one.
4. Add a cooldown window after disabling the built-in display so it would not immediately bounce back on.
5. Add detailed logging for:
   - callback display IDs
   - per-display `builtin/online/active/enabled/mirrored` state
   - exact recovery decisions and skip reasons
6. Retry auto-recovery a few times with short delays when the first enable request appeared to succeed but did not visibly restore the panel.

## What failed

### 1. Display callback state was noisy

On the test machine:

- after unplugging the external display, the built-in display could appear as `offline`
- the external display could still be reported as `online`
- callback IDs did not provide a clean, reliable signal that the external had truly gone away

That made state-inference logic fragile.

### 2. The enable call could report success without visible recovery

The app sometimes logged:

- `Attempting to re-enable display 1`
- `Re-enabled Display 1`
- `Built-in display restored automatically`

But the built-in panel still did not actually come back on after unplugging the external display.

This means that in the unplug-recovery scenario, a successful return from `CGSConfigureDisplayEnabled(..., true)` was not a reliable confirmation that the hardware/display session really recovered.

### 3. Recovery logic could interfere with intentional disable

Some versions of the logic caused the built-in display to switch back on immediately after the user intentionally disabled it, because the app saw a transient `1 enabled` state and interpreted that as a cue to recover.

Cooldown logic reduced this, but did not solve the core unplug-recovery problem.

### 4. Reconnect events could also trigger unwanted re-enable

In some callback sequences, reconnecting or other display churn would also trigger recovery logic, which was not desirable.

## Current conclusion

Automatic unplug recovery is not reliable enough with the current CGS callback/state-driven approach.

The app is stable and useful in this form:

- manual disable works
- manual re-enable works
- global hotkey recovery for the built-in display is available while the app is running:
  - `Shift-Control-Option-Command-D`

The app is not currently reliable for:

- automatic restoration of the built-in display after unplugging the external display

## What changed after the auto-recovery experiments

The auto-detection path was removed from the app after the callback/state-driven approach continued to fail on real unplug tests.

The replacement recovery approach is intentionally explicit:

- keep the app running
- if the built-in display was disabled and the external display is no longer usable, press `Shift-Control-Option-Command-D`
- the app will try to re-enable the built-in display directly through the existing CGS enable path

This does not solve accidental unplug automatically, but it gives the user a deterministic manual recovery shortcut without relying on noisy unplug detection.

## Likely next directions if revisited

1. Keep the app intentionally manual and prefer the hotkey/manual recovery path over automatic recovery logic.
2. Investigate whether built-in restoration needs a different private API than general display enable.
3. Revisit the SkyLight/clamshell-specific path only for built-in-display restoration.
4. Test whether a different completion scope such as session-scoped configuration behaves differently from `.permanently`.

## Summary

Auto-recovery was explored in multiple ways, but on the current test setup it was not dependable.

The safest current outcome is to keep the app as a manual display disable/re-enable tool, use the built-in-display hotkey as the recovery shortcut, and treat true automatic restoration as future research.
