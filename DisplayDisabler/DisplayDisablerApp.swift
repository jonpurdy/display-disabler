import SwiftUI
import ServiceManagement

@main
struct DisplayDisablerApp: App {
    @StateObject private var manager = DisplayManager()

    var body: some Scene {
        Window("Display Disabler", id: "main") {
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

        MenuBarExtra("Display Disabler", systemImage: "display.2") {
            DisplayMenu(manager: manager)
        }
    }
}

private struct DisplayMenu: View {
    @ObservedObject var manager: DisplayManager
    @Environment(\.openWindow) private var openWindow
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Text(manager.stateSummary)

        Button(manager.builtInToggleTitle) {
            manager.toggleBuiltInDisplay()
        }
        .disabled(!manager.canToggleBuiltInDisplay)

        if let error = manager.errorMessage ?? loginError {
            Text(error)
        }

        Divider()

        Button("Open Display Disabler…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Toggle("Start at Login", isOn: Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                } catch {
                    loginError = "Could not change Start at Login: \(error.localizedDescription)"
                }
                loginStatus = SMAppService.mainApp.status
                if loginStatus == .requiresApproval {
                    loginError = "Allow Display Disabler in System Settings > General > Login Items."
                }
            }
        ))

        Divider()

        Button("Quit Display Disabler") {
            NSApp.terminate(nil)
        }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval {
                loginError = "Allow Display Disabler in System Settings > General > Login Items."
            }
        }
    }
}
