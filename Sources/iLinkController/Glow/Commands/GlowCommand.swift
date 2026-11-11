enum GlowColor: String, CaseIterable, Identifiable {
    case red
    case green
    case blue
    case white
    case warmWhite
    case coolWhite
    case purple
    case pink
    case yellow
    case cyan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        case .white: "White"
        case .warmWhite: "Warm White"
        case .coolWhite: "Cool White"
        case .purple: "Purple"
        case .pink: "Pink"
        case .yellow: "Yellow"
        case .cyan: "Cyan"
        }
    }
}

enum GlowCommand: Equatable, Identifiable {
    case powerOn
    case powerOff
    case setBrightness(Int)
    case setColor(GlowColor)
    case checkConnection
    case reconnect
    case unknown

    var id: String {
        switch self {
        case .powerOn: "powerOn"
        case .powerOff: "powerOff"
        case let .setBrightness(value): "setBrightness-\(value)"
        case let .setColor(color): "setColor-\(color.rawValue)"
        case .checkConnection: "checkConnection"
        case .reconnect: "reconnect"
        case .unknown: "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .powerOn: "Turn Light On"
        case .powerOff: "Turn Light Off"
        case let .setBrightness(value): "Set Brightness to \(value)%"
        case let .setColor(color): "Set Color to \(color.displayName)"
        case .checkConnection: "Check Connection"
        case .reconnect: "Reconnect to Light"
        case .unknown: "Unknown Command"
        }
    }
}