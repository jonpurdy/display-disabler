import CoreGraphics

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let isOnline: Bool
    let isActive: Bool
    let isInMirrorSet: Bool

    var isEnabled: Bool {
        isOnline && (isActive || isInMirrorSet)
    }

    var badges: [String] {
        var values: [String] = []
        if isBuiltin {
            values.append("Built-in")
        }
        if isMain {
            values.append("Main")
        }
        values.append(stateLabel)
        if isInMirrorSet {
            values.append("Mirrored")
        }
        return values
    }

    var summaryText: String {
        "\(name) (ID \(id)) • \(badges.joined(separator: ", "))"
    }

    var stateLabel: String {
        if isEnabled {
            return "Enabled"
        }
        if isOnline {
            return "Disabled"
        }
        return "Offline"
    }
}

enum DisplayDisableError: Error, LocalizedError {
    case onlyOneDisplay
    case displayNotFound
    case noActiveFallbackDisplay
    case beginConfigurationFailed(CGError)
    case configureFailed(CGError)
    case completeFailed(CGError)

    var errorDescription: String? {
        switch self {
        case .onlyOneDisplay:
            return "Only one display is active. Connect an external display before disabling a monitor."
        case .displayNotFound:
            return "The selected display could not be found."
        case .noActiveFallbackDisplay:
            return "No fallback display is active, so windows cannot be moved safely."
        case .beginConfigurationFailed(let error):
            return "Beginning the display configuration failed with CGError \(error.rawValue)."
        case .configureFailed(let error):
            return "Changing the display configuration failed with CGError \(error.rawValue)."
        case .completeFailed(let error):
            return "Completing the display configuration failed with CGError \(error.rawValue)."
        }
    }
}
