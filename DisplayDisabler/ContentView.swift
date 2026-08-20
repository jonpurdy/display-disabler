import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Disabler")
                .font(.largeTitle.weight(.semibold))

            Text(manager.statusMessage)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(manager.stateSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage = manager.errorMessage {
                MessageBox(text: errorMessage, tint: .red)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Built-in Display")
                    .font(.headline)

                if let builtInDisplay = manager.builtInDisplay {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(builtInDisplay.name)
                                .font(.headline)
                            Text("Display ID \(builtInDisplay.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            ForEach(builtInDisplay.badges, id: \.self) { badge in
                                BadgeView(text: badge)
                            }
                        }
                    }
                } else {
                    Text("No built-in display was detected.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Refresh") {
                        manager.refreshDisplays()
                    }

                    Spacer()

                    Button(manager.builtInToggleTitle) {
                        manager.toggleBuiltInDisplay()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.canToggleBuiltInDisplay)
                }
            }
            .padding(14)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text("Hotkey")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("Toggle Built-in Display") {
                        manager.toggleBuiltInDisplay()
                    }
                    .disabled(!manager.canToggleBuiltInDisplay)

                    Text(manager.recoveryShortcutHint)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(manager.recoveryExplanation)
                    .font(.subheadline)

                Text(manager.recoveryNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Activity")
                        .font(.headline)

                    Spacer()

                    Button("Copy Built-in Summary") {
                        manager.copyBuiltInDisplaySummary()
                    }
                    .disabled(manager.builtInDisplay == nil)

                    Button("Copy Activity Log") {
                        manager.copyActivityLog()
                    }
                    .disabled(manager.eventLog.isEmpty)
                }

                ScrollView {
                    Text(manager.eventLogText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 180)
                .padding(10)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 540)
        .background(WindowAutosaveAccessor())
    }
}

private struct BadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

private struct MessageBox: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct WindowAutosaveAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.setFrameAutosaveName("DisplayDisablerMainWindow")
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.setFrameAutosaveName("DisplayDisablerMainWindow")
            }
        }
    }
}
