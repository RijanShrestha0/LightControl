enum GlowAssistantState: String {
    case disabled
    case requestingPermission
    case ready
    case capturingAudio
    case requestingSpeechPermission
    case checkingOfflineSupport
    case recognizingSpeech
    case recognitionCompleted
    case recognitionUnavailable
    case error

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .requestingPermission: "Requesting Microphone Access"
        case .ready: "Ready"
        case .capturingAudio: "Microphone Active"
        case .requestingSpeechPermission: "Requesting Speech Permission"
        case .checkingOfflineSupport: "Checking Offline Recognition"
        case .recognizingSpeech: "Listening"
        case .recognitionCompleted: "Recognition Complete"
        case .recognitionUnavailable: "Recognition Unavailable"
        case .error: "Needs Attention"
        }
    }
}