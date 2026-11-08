enum GlowAssistantState: String {
    case disabled
    case requestingPermission
    case ready
    case capturingAudio
    case error

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .requestingPermission: "Requesting Microphone Access"
        case .ready: "Ready"
        case .capturingAudio: "Microphone Active"
        case .error: "Needs Attention"
        }
    }
}