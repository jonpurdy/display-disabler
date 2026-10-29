# AGENTS.md — Display Disabler

## Scope

Maintain a minimal native Swift + SwiftUI macOS app for toggling the built-in MacBook display while an external display is active.

- Target macOS 15 (Sequoia), primarily Apple Silicon MacBooks.
- Keep a normal foreground app window. No menu bar app or background helper.
- Control only the built-in display. Enumerate external displays to determine whether disabling is safe.
- Remove the display from the active macOS layout; do not simulate disabling with brightness.

## Display backend

Keep private API declarations in `DisplayDisabler/CGSBridge.h` and display operations in `DisplayManager.swift`.

- Enumerate with `CGSGetDisplayList`, falling back to `CGGetOnlineDisplayList`.
- Treat a display as enabled when it is online and active or mirrored, as defined by `DisplayInfo.isEnabled`.
- Use `CGBeginDisplayConfiguration`, `CGSConfigureDisplayEnabled`, and `CGCompleteDisplayConfiguration(..., .permanently)` for manual disable/enable.
- Break mirroring before disabling a mirrored display.
- Refresh display state before validating a disable operation. Never disable the last enabled display; the built-in display requires an enabled external fallback.
- Preserve the last known built-in display ID in memory so manual enable can be attempted if it disappears from enumeration. Do not assume that ID survives relaunch.
- Refresh on launch, after actions, and through `CGDisplayRegisterReconfigurationCallback`. Remove callbacks and unregister the hotkey on teardown.
- Surface failures in the window and log CGError values. A successful API return does not guarantee visible panel recovery.

Keep the stable backend on CGS. SkyLight clamshell APIs are experimental and may require private Apple entitlements. Do not add them without a specific need and hardware testing; isolate any experiment and report failures honestly.

## UI and shortcuts

Keep one simple window with:

- Built-in display name, ID, state badges, and an external-display status summary.
- A clear message when no external display is active or no built-in display is found.
- **Refresh** and a state-dependent **Disable Built-in Display** / **Enable Built-in Display** button.
- **Toggle Built-in Display** and the global shortcut **Shift-Control-Option-Command-D**.
- A compact activity log, **Copy Built-in Summary**, and **Copy Activity Log**.
- Visible errors and recovery guidance.

The **Displays** menu provides refresh, disable, enable, and toggle actions. **Command-R** refreshes. The global toggle works while the app is running, including when another app is foreground. Apply the same last-display safeguard to every disable entry point.

Disable controls must be unavailable without an enabled external display. Enable controls may use the cached built-in ID when the display is missing from enumeration.

## Recovery

Keep recovery manual. Do not automatically re-enable on unplug, reconnect, or quit.

Document these options in the UI or README:

- While the app is running, **Shift-Control-Option-Command-D** toggles the built-in display and attempts to restore it when disabled or unavailable.
- Use **Enable Built-in Display** in the app or **Displays** menu.
- Reconnect the external display, then refresh or relaunch the app. Relaunch clears the cached built-in ID.
- Use **System Settings > Displays** if macOS still sees the display.
- Resetting WindowServer display persistence files is a manual last resort. Never automate deletion.

Read `autorecovery.md` before revisiting automatic recovery. Keep experimental findings there.

## Logging

Use `Logger` / `os.log` for enumeration, target display IDs, enabled-display count, backend, and configuration errors. Log hotkey registration success/failure and toggle attempts. Mirror recent actions and failures into the bounded in-window activity log.

## Build and verification

Use the Xcode project at `DisplayDisabler/DisplayDisabler.xcodeproj`. See `README.md` for requirements and build/run commands; keep those instructions current.

Code signing and App Sandbox are disabled for the local prototype. Do not add private entitlements as a workaround.

For display-behavior changes, build the app and verify on hardware that:

1. The app opens as a normal window and reports display state clearly.
2. Disabling requires an enabled external display and never disables the last enabled display.
3. Manual disable, enable, and the global toggle work, with state refreshed afterward.
4. Errors are visible and diagnostic information can be copied.

Do not claim hardware behavior was verified from a successful build alone.

## Non-goals

No external-monitor controls, brightness or DDC/CI control, login items, daemons, helpers, automatic disable-on-connect, automatic unplug recovery, display arrangement/resolution editing, virtual displays, network features, auto-update, or analytics.

## Background references

Consult these before changing private display behavior:

- [MonitorControl disable/hide discussion](https://github.com/MonitorControl/MonitorControl/issues/907): layout deactivation differs from brightness control.
- [DisableMonitor implementation](https://github.com/Eun/DisableMonitor/blob/3a690419041ae78cb4d776f2cb07919356817b49/DisableMonitorAppDelegate.m#L303): CGS configuration approach.
- [Lunar clamshell research](https://alinpanaitiu.com/blog/turn-off-macbook-display-clamshell/): built-in display power control and entitlement limitations.
