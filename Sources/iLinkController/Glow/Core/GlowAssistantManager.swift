import AVFoundation
import Combine
import Speech

@MainActor
final class GlowAssistantManager: ObservableObject {
    @Published private(set) var state: GlowAssistantState = .disabled
    @Published private(set) var errorMessage: String?
    @Published private(set) var interpretedCommand: GlowCommand = .unknown

    let permissionManager: GlowPermissionManager
    let audioCaptureManager: GlowAudioCaptureManager
    let speechRecognitionManager: GlowSpeechRecognitionManager

    private var enableRequestID: UUID?
    private var speechStartRequestID: UUID?

    init() {
        permissionManager = GlowPermissionManager()
        audioCaptureManager = GlowAudioCaptureManager()
        speechRecognitionManager = GlowSpeechRecognitionManager()
        bindAudioCaptureFailures()
    }

    init(permissionManager: GlowPermissionManager, audioCaptureManager: GlowAudioCaptureManager) {
        self.permissionManager = permissionManager
        self.audioCaptureManager = audioCaptureManager
        speechRecognitionManager = GlowSpeechRecognitionManager()
        bindAudioCaptureFailures()
    }

    init(
        permissionManager: GlowPermissionManager,
        audioCaptureManager: GlowAudioCaptureManager,
        speechRecognitionManager: GlowSpeechRecognitionManager
    ) {
        self.permissionManager = permissionManager
        self.audioCaptureManager = audioCaptureManager
        self.speechRecognitionManager = speechRecognitionManager
        bindAudioCaptureFailures()
    }

    private func bindAudioCaptureFailures() {
        audioCaptureManager.onCaptureFailure = { [weak self] message in
            self?.setError(message)
        }
        speechRecognitionManager.onRecognitionCompleted = { [weak self] _ in
            guard let self, self.state != .disabled else { return }
            self.speechStartRequestID = nil
            self.errorMessage = nil
            self.state = .recognitionCompleted
        }
        speechRecognitionManager.onRecognitionFailure = { [weak self] message in
            guard let self, self.state != .disabled else { return }
            self.speechStartRequestID = nil
            self.errorMessage = message
            self.state = .recognitionUnavailable
        }
        speechRecognitionManager.onRecognizedTextChanged = { [weak self] text in
            guard let self else { return }
            interpretedCommand = commandInterpreter.interpret(text)
        }
    }

    private let commandInterpreter = GlowCommandInterpreter()

    func enable() async {
        guard state == .disabled || state == .error || state == .recognitionUnavailable || state == .recognitionCompleted else { return }

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
        speechStartRequestID = nil
        speechRecognitionManager.cancelRecognition()
        audioCaptureManager.stopCapture()
        errorMessage = nil
        state = .disabled
    }

    func requestSpeechPermission() async -> Bool {
        let requestID = UUID()
        speechStartRequestID = requestID
        let authorized = await authorizeSpeechRecognition(for: requestID)
        guard speechStartRequestID == requestID else { return false }
        if authorized {
            speechStartRequestID = nil
            state = audioCaptureManager.isCapturing ? .capturingAudio : .ready
        }
        return authorized
    }

    func startSpeechRecognition() async {
        guard state != .requestingPermission,
              state != .requestingSpeechPermission,
              state != .checkingOfflineSupport,
              state != .recognizingSpeech else { return }

        let requestID = UUID()
        speechStartRequestID = requestID
        errorMessage = nil

        if !audioCaptureManager.isCapturing {
            state = .requestingPermission
            let microphoneStatus = await permissionManager.requestWhenEnablingGlow()
            guard speechStartRequestID == requestID else { return }
            guard microphoneStatus == .authorized else {
                setError(permissionManager.permissionExplanation ?? "Microphone access is required for Glow.")
                return
            }
        }

        guard await authorizeSpeechRecognition(for: requestID), speechStartRequestID == requestID else { return }

        state = .checkingOfflineSupport
        guard speechRecognitionManager.checkOfflineRecognitionSupport() else {
            speechStartRequestID = nil
            errorMessage = speechRecognitionManager.offlineSupportDescription
            state = .recognitionUnavailable
            return
        }

        do {
            if !audioCaptureManager.isCapturing {
                try audioCaptureManager.startCapture()
            }
            state = .recognizingSpeech
            try speechRecognitionManager.startRecognition(using: audioCaptureManager)
            speechStartRequestID = nil
        } catch {
            speechStartRequestID = nil
            errorMessage = error.localizedDescription
            state = .recognitionUnavailable
        }
    }

    func stopSpeechRecognition() {
        speechStartRequestID = nil
        speechRecognitionManager.stopRecognition()
        if state != .disabled {
            state = .recognitionCompleted
        }
    }

    func clearRecognizedText() {
        speechRecognitionManager.clearRecognizedText()
        interpretedCommand = .unknown
    }

    func toggle() async {
        switch state {
        case .disabled, .error, .recognitionUnavailable, .recognitionCompleted:
            await enable()
        case .requestingPermission, .ready, .capturingAudio,
             .requestingSpeechPermission, .checkingOfflineSupport, .recognizingSpeech:
            disable()
        }
    }

    private func setError(_ message: String) {
        enableRequestID = nil
        speechStartRequestID = nil
        speechRecognitionManager.cancelRecognition()
        audioCaptureManager.stopCapture()
        errorMessage = message
        state = .error
    }

    private func authorizeSpeechRecognition(for requestID: UUID) async -> Bool {
        state = .requestingSpeechPermission
        let status = await speechRecognitionManager.requestSpeechPermission()
        guard speechStartRequestID == requestID else { return false }
        guard status == .authorized else {
            errorMessage = speechPermissionMessage(for: status)
            state = .recognitionUnavailable
            return false
        }
        return true
    }

    private func speechPermissionMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            "Speech recognition access is denied. Allow it in System Settings to use local transcription."
        case .restricted:
            "Speech recognition access is restricted on this Mac."
        case .notDetermined:
            "Speech recognition permission was not resolved. Try again."
        case .authorized:
            ""
        @unknown default:
            "Speech recognition permission is unavailable."
        }
    }
}