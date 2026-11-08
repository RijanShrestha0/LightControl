import AVFoundation
import Combine

@MainActor
final class GlowAssistantManager: ObservableObject {
    @Published private(set) var state: GlowAssistantState = .disabled
    @Published private(set) var errorMessage: String?

    let permissionManager: GlowPermissionManager
    let audioCaptureManager: GlowAudioCaptureManager

    private var enableRequestID: UUID?

    init() {
        permissionManager = GlowPermissionManager()
        audioCaptureManager = GlowAudioCaptureManager()
        bindAudioCaptureFailures()
    }

    init(permissionManager: GlowPermissionManager, audioCaptureManager: GlowAudioCaptureManager) {
        self.permissionManager = permissionManager
        self.audioCaptureManager = audioCaptureManager
        bindAudioCaptureFailures()
    }

    private func bindAudioCaptureFailures() {
        audioCaptureManager.onCaptureFailure = { [weak self] message in
            self?.setError(message)
        }
    }

    func enable() async {
        guard state == .disabled || state == .error else { return }

        let requestID = UUID()
        enableRequestID = requestID
        errorMessage = nil
        state = .requestingPermission

        let authorization = await permissionManager.requestWhenEnablingGlow()
        guard enableRequestID == requestID else { return }

        switch authorization {
        case .authorized:
            state = .ready
        case .denied:
            setError("Microphone access is denied. Allow it in System Settings to enable Glow.")
            return
        case .restricted:
            setError("Microphone access is restricted on this Mac.")
            return
        case .notDetermined:
            setError("Microphone permission was not resolved. Try enabling Glow again.")
            return
        @unknown default:
            setError("Microphone permission status is unavailable.")
            return
        }

        do {
            try audioCaptureManager.startCapture()
            state = .capturingAudio
        } catch {
            setError("Glow could not start microphone capture: \(error.localizedDescription)")
        }
    }

    func disable() {
        enableRequestID = nil
        audioCaptureManager.stopCapture()
        errorMessage = nil
        state = .disabled
    }

    func toggle() async {
        switch state {
        case .disabled, .error:
            await enable()
        case .requestingPermission, .ready, .capturingAudio:
            disable()
        }
    }

    private func setError(_ message: String) {
        enableRequestID = nil
        audioCaptureManager.stopCapture()
        errorMessage = message
        state = .error
    }
}