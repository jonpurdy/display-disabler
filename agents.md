# AGENT.md — Minimal macOS Display Disabler App

## Goal

Build a minimal native macOS app for macOS Sequoia that can disable one connected monitor when more than one display is available.

The app should be a normal foreground app with a window. Do not make it a menu bar app.

Primary user story:

- User opens the app.
- App lists connected displays.
- If only the internal MacBook display is available, show a clear message that there is no other display connected and do not offer a disable action.
- If multiple displays are connected, let the user select a display and disable it.
- Prefer disabling the selected display from the macOS display layout, not merely setting brightness to zero.
- User can manually re-enable a previously disabled display from the app.
- If the built-in display was disabled and the external display is later unavailable, user can press `Shift-Control-Option-Command-D` while the app is running to try to re-enable the built-in display.

## Target platform

- macOS Sequoia.
- Apple Silicon MacBook is the main target.
- Use Swift + SwiftUI unless a small Objective-C bridge is needed for private CoreGraphics / SkyLight symbols.
- Keep the app small and understandable.
- No login item, daemon, helper tool, menu bar extra, background agent, auto-update, or analytics.

## Important sources to study

Use these sources before coding:

1. MonitorControl issue requesting disable / hide display behavior:
   - https://github.com/MonitorControl/MonitorControl/issues/907?issue=MonitorControl%7CMonitorControl%7C1105
   - Key point: the requested behavior is specifically deactivating / hiding a display, not brightness control.

2. DisableMonitor implementation:
   - https://github.com/Eun/DisableMonitor/blob/3a690419041ae78cb4d776f2cb07919356817b49/DisableMonitorAppDelegate.m#L303
   - Raw source if GitHub page view is hard to read:
     - https://raw.githubusercontent.com/Eun/DisableMonitor/3a690419041ae78cb4d776f2cb07919356817b49/DisableMonitorAppDelegate.m
   - Key functions / ideas:
     - `CGSGetDisplayList`
     - `CGDisplayIsOnline`
     - `CGDisplayIsActive`
     - `CGDisplayIsInMirrorSet`
     - `CGBeginDisplayConfiguration`
     - `CGConfigureDisplayMirrorOfDisplay`
     - `CGSConfigureDisplayEnabled`
     - `CGCompleteDisplayConfiguration`
     - `IORegistryEntryFromPath(... "IOService:/IOResources/IODisplayWrangler")`
     - moving windows off the display before disabling it

3. Lunar clamshell reverse engineering:
   - https://alinpanaitiu.com/blog/turn-off-macbook-display-clamshell/
   - Key ideas:
     - Real clamshell mode removes the internal display from the screen list.
     - This is not the same as setting brightness to zero.
     - SkyLight has `SLSDisplayPowerControlClient`.
     - `kSLSDisplayControlRequestClamshellState` takes values:
       - `1` = clamshell open / re-enable internal display
       - `2` = clamshell closed / disable internal display
     - `powerd` uses the private entitlement `com.apple.private.SkyLight.displaypowercontrol`.
     - A third-party app may hit entitlement / AMFI restrictions when directly calling this path.

## Implementation strategy

Implement one stable backend and keep any experimental built-in-display work isolated.

### Backend A: general monitor disable via private CGS display configuration

Use this as the first implementation attempt.

Create a small Objective-C bridging header exposing the private symbols needed by DisableMonitor-style code.

Expected private calls:

```objc
CG_EXTERN CGError CGSGetDisplayList(CGDisplayCount maxDisplays,
                                    CGDirectDisplayID *displays,
                                    CGDisplayCount *displayCount);

CG_EXTERN CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef config,
                                             CGDirectDisplayID display,
                                             bool enabled);
```

Then implement Swift wrapper methods:

```swift
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let isOnline: Bool
    let isActive: Bool
    let isInMirrorSet: Bool
}

enum DisplayDisableError: Error, LocalizedError {
    case onlyOneDisplay
    case displayNotFound
    case noActiveFallbackDisplay
    case beginConfigurationFailed(CGError)
    case configureFailed(CGError)
    case completeFailed(CGError)
}
```

Functions:

```swift
func allDisplays() -> [DisplayInfo]
func activeDisplays() -> [DisplayInfo]
func disableDisplay(_ id: CGDirectDisplayID) throws
func enableDisplay(_ id: CGDirectDisplayID) throws
func refreshDisplays()
```

For display names, use `IODisplayCreateInfoDictionary` via the display service port when possible. Fallback to `Display <id>`.

Before disabling:

1. Refresh active displays.
2. If active display count is less than or equal to 1, throw `.onlyOneDisplay`.
3. If selected display is the only active display, refuse.
4. Pick another active display as fallback.
5. Begin display config.
6. If the display is mirrored, break mirroring with:
   ```objc
   CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
   ```
7. Call:
   ```objc
   CGSConfigureDisplayEnabled(config, displayID, false)
   ```
8. Complete with:
   ```objc
   CGCompleteDisplayConfiguration(config, kCGConfigurePermanently)
   ```

Use `kCGConfigurePermanently` to match DisableMonitor. If this causes problems on Sequoia, test `kCGConfigureForSession` as a fallback and document the behavior.

Manual re-enable:

1. Refresh displays.
2. Allow selecting a display that is present but not enabled.
3. Begin display config.
4. Call:
   ```objc
   CGSConfigureDisplayEnabled(config, displayID, true)
   ```
5. Complete with:
   ```objc
   CGCompleteDisplayConfiguration(config, kCGConfigurePermanently)
   ```

### Backend B: MacBook internal-display clamshell special case

Use only as an experimental path for the built-in display on Apple Silicon MacBooks when the normal CGS enable path is not sufficient.

This path should be implemented as an experimental fallback or clearly isolated backend. Do not make the entire app depend on it.

Bridge the relevant SkyLight symbols only if needed:

```objc
#import <Foundation/Foundation.h>

@interface SLSDisplayPowerControlClient : NSObject
- (id)initAsyncPowerControlClient:(id *)error
                      notifyQueue:(id)queue
                  notificationType:(UInt8)notificationType
                 notificationBlock:(void (^)(NSDictionary *notification))notificationBlock;

- (unsigned long long)requestStateChange:(id)request error:(id *)error;
@end

extern NSString *kSLSDisplayControlRequestClamshellState;
```

Swift shape:

```swift
enum ClamshellState: Int {
    case open = 1
    case closed = 2
    case unknown = 3
    case doesNotExist = 4
}

func requestClamshellState(_ state: ClamshellState) throws
```

Request dictionary:

```swift
[
    kSLSDisplayControlRequestClamshellState: NSNumber(value: state.rawValue)
]
```

Expected behavior:

- `.closed` should disable the internal display while leaving external displays active.
- `.open` may be useful for future built-in-display restoration experiments.

Important: this may fail for a third-party app because `powerd` uses `com.apple.private.SkyLight.displaypowercontrol`. Do not fake success. Surface the error in the UI and log it.

## UI requirements

Use SwiftUI.

Single window layout:

- Title: `Display Disabler`
- Status area:
  - If only one active display: `Only one display is active. Connect an external display before disabling a monitor.`
  - If multiple active displays: `Select a display to disable or re-enable.`
- Display list:
  - Display name
  - Badges: `Built-in`, `Main`, `Enabled`, `Disabled`, `Offline`, `Mirrored`
- Buttons:
  - `Refresh`
  - `Re-enable Selected Display`
  - `Disable Selected Display`
- Secondary status / notes:
  - Compact state summary such as enabled / disabled / offline counts
  - Recovery note telling the user how to manually recover, including the global hotkey
  - Small in-window activity log for recent actions and refreshes
- Disable button rules:
  - Disabled if there is only one active display.
  - Disabled if no display is selected.
  - Disabled if selecting the only active display.
- Re-enable button rules:
  - Disabled if no display is selected.
  - Disabled if the selected display is already enabled.
- Show errors in the window, not only in Console.

Do not use a menu bar icon.

## App lifecycle

On launch:

1. Enumerate displays.
2. Register a display reconfiguration callback:
   ```swift
   CGDisplayRegisterReconfigurationCallback(...)
   ```
3. Register a global hotkey:
   - `Shift-Control-Option-Command-D`
4. Refresh the list when displays are added, removed, enabled, disabled, or reconfigured.

On quit:

- Do not automatically re-enable displays unless that behavior is explicitly implemented and visible to the user.
- If clamshell backend was used, consider offering an in-window `Re-enable Built-in Display` button.

## Safety / recovery behavior

The app must not let the user disable the last active display.

Also include a small recovery note in the UI or README:

- While the app is running, press `Shift-Control-Option-Command-D` to try to re-enable the built-in display.
- Reconnect the disabled display.
- Relaunch the app and refresh.
- Use the in-app `Re-enable Selected Display` action when the disabled display is still listed.
- Use System Settings > Displays if macOS still sees the monitor.
- If display layout becomes corrupted, deleting WindowServer display persistence files may reset macOS display configuration. Do not automate this.

Do not rely on automatic unplug recovery in the stable app. The stable recovery path is manual re-enable plus the global built-in-display hotkey. Experimental notes about attempted auto-recovery behavior belong in `autorecovery.md`.

## Logging

Use `Logger` / `os.log`.

Log:

- Display enumeration result.
- Selected display ID.
- Active display count.
- Backend used.
- CGError values from begin/configure/complete.
- SkyLight errors if clamshell backend is attempted.
- Hotkey registration success or failure.
- Hotkey-triggered built-in re-enable attempts.
- Recent user-visible actions should also be mirrored into the in-window activity log.

## Build notes

Use an Xcode macOS app project.

Suggested files:

```text
DisplayDisabler/
  DisplayDisablerApp.swift
  ContentView.swift
  DisplayManager.swift
  DisplayInfo.swift
  CGSBridge.h
```

Build settings:

- Add bridging header.
- Link private framework only if using SkyLight:
  - `-F/System/Library/PrivateFrameworks`
  - `-framework SkyLight`
- Do not sandbox for the first prototype. If sandboxing breaks private display configuration, keep it off and document why.

## Acceptance criteria

A successful prototype should:

1. Launch as a normal app window.
2. Show active connected displays on Sequoia.
3. Show a useful message when only the internal display is active.
4. Allow disabling one display when at least two active displays exist.
5. Refuse to disable the last active display.
6. Refresh display state after changes.
7. Allow manually re-enabling a disabled display from the app.
8. Allow trying to re-enable the built-in display with `Shift-Control-Option-Command-D` while the app is running.
8. Not rely on setting brightness to zero.
9. Keep all private API usage isolated behind small wrappers.
10. Show any failure clearly in the UI.

## Non-goals

Do not implement:

- Brightness control.
- DDC / CI control.
- Menu bar controls.
- Keyboard shortcuts.
- Login item.
- Automatic disable-on-connect.
- Display arrangement editor.
- Resolution switching.
- Virtual displays.
- Network features.
- Auto-update.

## Notes for the coding agent

Start with Backend A. It is closest to the older DisableMonitor implementation and applies to arbitrary monitors.

Only add Backend B after Backend A is tested, because the SkyLight clamshell route is specifically about MacBook internal-display clamshell state and may require private Apple entitlements.

Keep the stable version boring: one window, one list, manual disable/re-enable actions, the built-in-display recovery hotkey, and clear errors.

If automatic built-in recovery is revisited later, read `autorecovery.md` first. The current stable app should stay manual-first, with the hotkey as the built-in-display recovery shortcut, unless a more reliable restore path is found.
