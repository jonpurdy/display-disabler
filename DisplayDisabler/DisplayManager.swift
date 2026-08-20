import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import OSLog
import SwiftUI

private let displayLogger = Logger(subsystem: "com.example.DisplayDisabler", category: "DisplayManager")
nonisolated(unsafe) private weak var registeredDisplayManager: DisplayManager?
nonisolated(unsafe) private weak var registeredHotKeyManager: DisplayManager?

private let restoreBuiltInHotKeySignature: OSType = 0x44444953 // "DDIS"
private let restoreBuiltInHotKeyID: UInt32 = 1

private func displayReconfigurationCallback(displayID: CGDirectDisplayID,
                                            flags: CGDisplayChangeSummaryFlags,
                                            userInfo: UnsafeMutableRawPointer?) {
    guard let manager = registeredDisplayManager else {
        return
    }
    displayLogger.info("Display reconfiguration callback for \(displayID, privacy: .public), flags: \(String(describing: flags), privacy: .public)")
    Task { @MainActor in
        manager.handleDisplayReconfiguration(displayID: displayID, flags: flags)
    }
}

private func hotKeyEventHandler(nextHandler: EventHandlerCallRef?,
                                event: EventRef?,
                                userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return status
    }

    guard hotKeyID.signature == restoreBuiltInHotKeySignature,
          hotKeyID.id == restoreBuiltInHotKeyID,
          let manager = registeredHotKeyManager else {
        return noErr
    }

    Task { @MainActor in
        manager.handleRestoreBuiltInHotKey()
    }
    return noErr
}

@MainActor
final class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var errorMessage: String?
    @Published private(set) var eventLog: [String] = []

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var hotKeyHandlerRef: EventHandlerRef?
    private var lastKnownBuiltInDisplayID: CGDirectDisplayID?
    private var lastKnownBuiltInDisplayName: String?

    init() {
        registeredDisplayManager = self
        registeredHotKeyManager = self
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        registerRestoreBuiltInHotKey()
        refreshDisplays()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
    }

    var enabledDisplays: [DisplayInfo] {
        displays.filter(\.isEnabled)
    }

    var builtInDisplay: DisplayInfo? {
        displays.first(where: \.isBuiltin)
    }

    var builtInDisplayName: String {
        builtInDisplay?.name ?? lastKnownBuiltInDisplayName ?? "Built-in Display"
    }

    var activeExternalDisplays: [DisplayInfo] {
        displays.filter { !$0.isBuiltin && $0.isEnabled }
    }

    var canDisableBuiltInDisplay: Bool {
        guard let builtInDisplay else {
            return false
        }
        return builtInDisplay.isEnabled && !activeExternalDisplays.isEmpty
    }

    var canEnableBuiltInDisplay: Bool {
        if let builtInDisplay {
            return !builtInDisplay.isEnabled
        }
        return lastKnownBuiltInDisplayID != nil
    }

    var canToggleBuiltInDisplay: Bool {
        canDisableBuiltInDisplay || canEnableBuiltInDisplay
    }

    var builtInToggleTitle: String {
        if canEnableBuiltInDisplay {
            return "Enable Built-in Display"
        }
        return "Disable Built-in Display"
    }

    var eventLogText: String {
        eventLog.joined(separator: "\n")
    }

    var statusMessage: String {
        guard let builtInDisplay else {
            if lastKnownBuiltInDisplayID != nil {
                return "The built-in display is not currently visible in macOS. Use the button or hotkey to try to bring it back."
            }
            return "No built-in display was found."
        }

        if builtInDisplay.isEnabled {
            if activeExternalDisplays.isEmpty {
                return "Connect an external display before disabling the built-in display."
            }
            return "The built-in display is enabled. You can disable it while an external display is active."
        }

        return "The built-in display is disabled. Use the button or hotkey to bring it back."
    }

    var stateSummary: String {
        var parts: [String] = []
        if let builtInDisplay {
            parts.append("Built-in \(builtInDisplay.stateLabel.lowercased())")
        } else if lastKnownBuiltInDisplayID != nil {
            parts.append("Built-in unavailable")
        }
        if !activeExternalDisplays.isEmpty {
            parts.append("\(activeExternalDisplays.count) external active")
        } else {
            parts.append("No active external display")
        }
        return parts.joined(separator: " • ")
    }

    var recoveryNote: String {
        "While Display Disabler is running, Shift-Control-Option-Command-D toggles the built-in display from any foreground app."
    }

    var recoveryShortcutHint: String {
        "Shift-Control-Option-Command-D"
    }

    var recoveryExplanation: String {
        "Use the same shortcut to disable the built-in display when an external monitor is active, or to re-enable it later."
    }

    func refreshDisplays() {
        let refreshedDisplays = allDisplays()
        displays = refreshedDisplays

        if let builtInDisplay = refreshedDisplays.first(where: \.isBuiltin) {
            lastKnownBuiltInDisplayID = builtInDisplay.id
            lastKnownBuiltInDisplayName = builtInDisplay.name
        }

        let displaySummary = refreshedDisplays
            .map { "\($0.name) [id=\($0.id) online=\($0.isOnline) active=\($0.isActive) mirrored=\($0.isInMirrorSet)]" }
            .joined(separator: ", ")
        displayLogger.info("Display enumeration result: \(displaySummary, privacy: .public)")
        appendLog("Refreshed displays: \(stateSummary)")
    }

    func handleDisplayReconfiguration(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        appendLog("Reconfiguration callback for display \(displayID), flags: \(String(describing: flags))")
        refreshDisplays()
    }

    func disableBuiltInDisplay() {
        errorMessage = nil
        guard let builtInDisplay else {
            errorMessage = DisplayDisableError.displayNotFound.localizedDescription
            return
        }

        lastKnownBuiltInDisplayID = builtInDisplay.id
        lastKnownBuiltInDisplayName = builtInDisplay.name

        do {
            try disableDisplay(builtInDisplay.id)
            refreshDisplays()
        } catch {
            displayLogger.error("Disable built-in failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            refreshDisplays()
        }
    }

    func enableBuiltInDisplay() {
        errorMessage = nil

        do {
            try reEnableBuiltInDisplay()
            refreshDisplays()
        } catch {
            displayLogger.error("Enable built-in failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            refreshDisplays()
        }
    }

    func toggleBuiltInDisplay() {
        errorMessage = nil

        if canEnableBuiltInDisplay {
            appendLog("Toggle requested: enable built-in display.")
            enableBuiltInDisplay()
            return
        }

        appendLog("Toggle requested: disable built-in display.")
        disableBuiltInDisplay()
    }

    func handleRestoreBuiltInHotKey() {
        appendLog("Hotkey pressed: toggling built-in display.")
        toggleBuiltInDisplay()
    }

    func triggerBuiltInRecovery() {
        appendLog("Manual built-in toggle requested.")
        toggleBuiltInDisplay()
    }

    func copyBuiltInDisplaySummary() {
        if let builtInDisplay {
            copyToPasteboard(displaySummary(for: builtInDisplay), label: "built-in display summary")
            return
        }

        guard let lastKnownBuiltInDisplayID else {
            errorMessage = "No built-in display was found."
            return
        }

        let summary = "\(builtInDisplayName) (ID \(lastKnownBuiltInDisplayID)) • Unavailable"
        copyToPasteboard(summary, label: "built-in display summary")
    }

    func copyActivityLog() {
        copyToPasteboard(eventLogText, label: "activity log")
    }

    func displaySummary(for display: DisplayInfo) -> String {
        display.summaryText
    }

    func allDisplays() -> [DisplayInfo] {
        let ids = configuredDisplayIDs()
        return ids
            .map(makeDisplayInfo(for:))
            .sorted { lhs, rhs in
                if lhs.isMain != rhs.isMain {
                    return lhs.isMain && !rhs.isMain
                }
                if lhs.isBuiltin != rhs.isBuiltin {
                    return lhs.isBuiltin && !rhs.isBuiltin
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func activeDisplays() -> [DisplayInfo] {
        allDisplays().filter(\.isEnabled)
    }

    func disableDisplay(_ id: CGDirectDisplayID) throws {
        let displays = activeDisplays()
        displayLogger.info("Selected display ID: \(id, privacy: .public)")
        displayLogger.info("Active display count: \(displays.count, privacy: .public)")
        appendLog("Attempting to disable display \(id)")

        guard displays.count > 1 else {
            throw DisplayDisableError.onlyOneDisplay
        }

        guard let targetDisplay = displays.first(where: { $0.id == id }) else {
            throw DisplayDisableError.displayNotFound
        }

        guard displays.contains(where: { $0.id != id }) else {
            throw DisplayDisableError.noActiveFallbackDisplay
        }

        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            displayLogger.error("CGBeginDisplayConfiguration failed with \(beginError.rawValue, privacy: .public)")
            throw DisplayDisableError.beginConfigurationFailed(beginError)
        }

        if targetDisplay.isInMirrorSet {
            let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
            guard mirrorError == .success else {
                displayLogger.error("CGConfigureDisplayMirrorOfDisplay failed with \(mirrorError.rawValue, privacy: .public)")
                throw DisplayDisableError.configureFailed(mirrorError)
            }
        }

        let configureError = CGSConfigureDisplayEnabled(config, id, false)
        guard configureError == .success else {
            displayLogger.error("CGSConfigureDisplayEnabled(false) failed with \(configureError.rawValue, privacy: .public)")
            throw DisplayDisableError.configureFailed(configureError)
        }

        let completeError = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeError == .success else {
            displayLogger.error("CGCompleteDisplayConfiguration failed with \(completeError.rawValue, privacy: .public)")
            throw DisplayDisableError.completeFailed(completeError)
        }

        displayLogger.info("Backend used: Private CGS display configuration")
        appendLog("Disabled \(targetDisplay.name)")
    }

    func enableDisplay(_ id: CGDirectDisplayID) throws {
        displayLogger.info("Re-enabling display ID: \(id, privacy: .public)")
        appendLog("Attempting to re-enable display \(id)")
        let displayName = displays.first(where: { $0.id == id })?.name ?? lastKnownBuiltInDisplayName ?? "Display \(id)"

        try performEnableDisplay(id, option: .permanently, breakMirroring: false)

        displayLogger.info("Re-enabled display \(id, privacy: .public) using private CGS display configuration")
        appendLog("Re-enabled \(displayName)")
    }

    func reEnableBuiltInDisplay() throws {
        let knownDisplays = allDisplays()

        if let builtInDisabledDisplay = knownDisplays.first(where: { $0.isBuiltin && !$0.isEnabled }) {
            try enableDisplay(builtInDisabledDisplay.id)
            return
        }

        if let builtInEnabledDisplay = knownDisplays.first(where: { $0.isBuiltin && $0.isEnabled }) {
            appendLog("\(builtInEnabledDisplay.name) is already enabled.")
            return
        }

        if let lastKnownBuiltInDisplayID {
            appendLog("Built-in display is not currently listed; retrying enable using cached display ID \(lastKnownBuiltInDisplayID).")
            try enableDisplay(lastKnownBuiltInDisplayID)
            return
        }

        throw DisplayDisableError.displayNotFound
    }

    func performEnableDisplay(_ id: CGDirectDisplayID,
                              option: CGConfigureOption,
                              breakMirroring: Bool) throws {
        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            displayLogger.error("CGBeginDisplayConfiguration for enable failed with \(beginError.rawValue, privacy: .public)")
            throw DisplayDisableError.beginConfigurationFailed(beginError)
        }

        if breakMirroring, displays.first(where: { $0.id == id })?.isInMirrorSet == true {
            let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
            guard mirrorError == .success else {
                displayLogger.error("CGConfigureDisplayMirrorOfDisplay during recovery failed with \(mirrorError.rawValue, privacy: .public)")
                throw DisplayDisableError.configureFailed(mirrorError)
            }
        }

        let configureError = CGSConfigureDisplayEnabled(config, id, true)
        guard configureError == .success else {
            displayLogger.error("CGSConfigureDisplayEnabled(true) failed with \(configureError.rawValue, privacy: .public)")
            throw DisplayDisableError.configureFailed(configureError)
        }

        let completeError = CGCompleteDisplayConfiguration(config, option)
        guard completeError == .success else {
            displayLogger.error("CGCompleteDisplayConfiguration for enable failed with \(completeError.rawValue, privacy: .public)")
            throw DisplayDisableError.completeFailed(completeError)
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "\(formatter.string(from: Date()))  \(message)"
        eventLog.insert(entry, at: 0)
        if eventLog.count > 40 {
            eventLog.removeLast(eventLog.count - 40)
        }
    }

    private func copyToPasteboard(_ string: String, label: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        appendLog("Copied \(label) to the pasteboard.")
    }

    private func registerRestoreBuiltInHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &hotKeyHandlerRef
        )

        guard handlerStatus == noErr else {
            appendLog("Failed to install hotkey handler (\(handlerStatus)).")
            return
        }

        let hotKeyID = EventHotKeyID(signature: restoreBuiltInHotKeySignature, id: restoreBuiltInHotKeyID)
        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            appendLog("Registered global built-in toggle hotkey: Shift-Control-Option-Command-D.")
        } else {
            appendLog("Failed to register restore hotkey (\(registerStatus)).")
        }
    }

    private func configuredDisplayIDs() -> [CGDirectDisplayID] {
        var ids = Array(repeating: CGDirectDisplayID(), count: 16)
        var count: CGDisplayCount = 0

        let privateError = CGSGetDisplayList(CGDisplayCount(ids.count), &ids, &count)
        if privateError == .success, count > 0 {
            return Array(ids.prefix(Int(count)))
        }

        let publicError = CGGetOnlineDisplayList(CGDisplayCount(ids.count), &ids, &count)
        if publicError == .success {
            return Array(ids.prefix(Int(count)))
        }

        displayLogger.error("Unable to enumerate displays. Private error: \(privateError.rawValue, privacy: .public), public error: \(publicError.rawValue, privacy: .public)")
        return []
    }

    private func makeDisplayInfo(for displayID: CGDirectDisplayID) -> DisplayInfo {
        DisplayInfo(
            id: displayID,
            name: displayName(for: displayID),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            isMain: CGDisplayIsMain(displayID) != 0,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            isInMirrorSet: CGDisplayIsInMirrorSet(displayID) != 0
        )
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: {
            let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return screenNumber?.uint32Value == displayID
        }) {
            return screen.localizedName
        }

        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        let serialNumber = CGDisplaySerialNumber(displayID)

        guard let matching = IOServiceMatching("IODisplayConnect") else {
            return "Display \(displayID)"
        }

        var iterator: io_iterator_t = 0
        let matchingResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchingResult == KERN_SUCCESS else {
            return "Display \(displayID)"
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any] {
                let serviceVendorID = info[kDisplayVendorID as String] as? UInt32
                let serviceProductID = info[kDisplayProductID as String] as? UInt32
                let serviceSerial = info[kDisplaySerialNumber as String] as? UInt32

                if serviceVendorID == vendorID && serviceProductID == productID && (serviceSerial == nil || serviceSerial == serialNumber) {
                    if let productNames = info[kDisplayProductName as String] as? [String: String],
                       let bestName = productNames.values.first(where: { !$0.isEmpty }) {
                        return bestName
                    }
                }
            }

            service = IOIteratorNext(iterator)
        }

        return "Display \(displayID)"
    }
}
