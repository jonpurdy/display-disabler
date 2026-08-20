import SwiftUI

@main
struct DisplayDisablerApp: App {
    @StateObject private var manager = DisplayManager()

    var body: some Scene {
        WindowGroup("Display Disabler") {
            ContentView(manager: manager)
        }
        .defaultSize(width: 820, height: 560)
        .commands {
            CommandMenu("Displays") {
                Button("Refresh") {
                    manager.refreshDisplays()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Disable Built-in Display") {
                    manager.disableBuiltInDisplay()
                }
                .disabled(!manager.canDisableBuiltInDisplay)

                Button("Enable Built-in Display") {
                    manager.enableBuiltInDisplay()
                }
                .disabled(!manager.canEnableBuiltInDisplay)

                Divider()

                Button("Toggle Built-in Display") {
                    manager.toggleBuiltInDisplay()
                }
                .keyboardShortcut("d", modifiers: [.shift, .control, .option, .command])
                .disabled(!manager.canToggleBuiltInDisplay)
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Built-in Display Summary") {
                    manager.copyBuiltInDisplaySummary()
                }
                .disabled(manager.builtInDisplay == nil)

                Divider()

                Button("Copy Activity Log") {
                    manager.copyActivityLog()
                }
                .disabled(manager.eventLog.isEmpty)
            }
        }
    }
}
