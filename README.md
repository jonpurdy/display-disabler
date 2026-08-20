# Display Disabler

Minimal native macOS app for toggling the built-in MacBook display while an external display is connected.

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
