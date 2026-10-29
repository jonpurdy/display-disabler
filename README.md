# Display Disabler

Minimal native macOS app for toggling the built-in MacBook display while an external display is connected.

## Requirements

- macOS 15 (Sequoia) or later; Sequoia is the target platform.
- Xcode 16 or later (Swift 6 toolchain) to build.
- A MacBook with a built-in display; Apple Silicon is the primary target.
- An active external display to disable the built-in display safely.

## Build

From the project root:

```bash
xcodebuild \
  -project DisplayDisabler/DisplayDisabler.xcodeproj \
  -scheme DisplayDisabler \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  build
```

Output:

- `build/DerivedData/Build/Products/Debug/DisplayDisabler.app`

Or open `DisplayDisabler/DisplayDisabler.xcodeproj` in Xcode, select the **DisplayDisabler** scheme and **My Mac** destination, and build with **Command-B**.

## Run

Double-click the built `.app`, or launch it from the project root:

```bash
open build/DerivedData/Build/Products/Debug/DisplayDisabler.app
```

In Xcode, run with **Command-R**.

The project disables code signing and App Sandbox for this local prototype. The app is not notarized.

## Usage

1. Connect an external display and open Display Disabler.
2. Check the built-in display's status and badges in the app window. Click **Refresh** to update the state manually.
3. Click **Disable Built-in Display** to remove it from the active display layout. This action is unavailable unless an external display is active.
4. Click **Enable Built-in Display** to restore it, or use **Toggle Built-in Display** to switch its state.

While the app is running, **Shift-Control-Option-Command-D** toggles the built-in display from any foreground app. The **Displays** menu also provides enable, disable, toggle, and refresh actions.

Errors appear in the window. Use **Copy Built-in Summary** or **Copy Activity Log** to copy diagnostic details when troubleshooting.

## Notes

- The app uses a private CoreGraphics Services symbol, `CGSConfigureDisplayEnabled`, to remove the built-in display from the active layout instead of faking the effect with brightness.
- The app only controls the built-in display.
- The app refuses to disable the built-in display unless an external display is active.
- Private APIs can change across macOS releases. This project targets macOS Sequoia for local experimentation.

## Recovery

- While the app is running, press `Shift-Control-Option-Command-D` from any foreground app to toggle the built-in display.
- Or use the in-window `Disable Built-in Display`, `Enable Built-in Display`, or `Toggle Built-in Display` actions.
- If macOS still sees the display, use System Settings > Displays to reconfigure it.
- If display layout persistence becomes corrupted, reset WindowServer display persistence files manually. This app does not automate that.
