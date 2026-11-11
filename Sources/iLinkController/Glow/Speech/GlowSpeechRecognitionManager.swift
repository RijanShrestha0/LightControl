import Combine
import Foundation
import Speech

@MainActor
final class GlowSpeechRecognitionManager: ObservableObject {
    @Published private(set) var authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @Published private(set) var offlineSupportDescription = "Not checked"
    @Published private(set) var isOfflineRecognitionAvailable = false
    @Published private(set) var isRecognizing = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var isPartialResult = false
    @Published private(set) var errorMessage: String?

    var onRecognitionCompleted: ((String) -> Void)?
    var onRecognitionFailure: ((String) -> Void)?
    var onRecognizedTextChanged: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private weak var audioCaptureManager: GlowAudioCaptureManager?
    private var activeSessionID: UUID?
    private var isStopping = false

    var authorizationDescription: String {
        switch authorizationStatus {
        case .authorized: "Speech recognition allowed"
        case .denied: "Speech recognition denied"
        case .restricted: "Speech recognition restricted"
        case .notDetermined: "Speech recognition not requested"
        @unknown default: "Speech recognition unavailable"
        }
    }

    func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        guard authorizationStatus == .notDetermined else { return authorizationStatus }

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        return status
    }

    @discardableResult
    func checkOfflineRecognitionSupport() -> Bool {
        let locale = Locale.current
        let languageCode = locale.identifier.split(separator: "_").first?.split(separator: "-").first.map(String.init)

        guard languageCode == "en" else {
            recognizer = nil
            isOfflineRecognitionAvailable = false
            offlineSupportDescription = "Offline English recognition is unavailable for system locale \(locale.identifier). Set macOS to an English locale to use Glow speech recognition."
            return false
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            self.recognizer = nil
            isOfflineRecognitionAvailable = false
            offlineSupportDescription = "No speech recognizer is available for \(locale.identifier)."
            return false
        }

        guard recognizer.supportsOnDeviceRecognition else {
            self.recognizer = nil
            isOfflineRecognitionAvailable = false
            offlineSupportDescription = "On-device recognition is not supported for \(locale.identifier). Glow will not use network recognition."
            return false
        }

        guard recognizer.isAvailable else {
            self.recognizer = nil
            isOfflineRecognitionAvailable = false
            offlineSupportDescription = "The on-device recognizer for \(locale.identifier) is temporarily unavailable."
            return false
        }

        self.recognizer = recognizer
        isOfflineRecognitionAvailable = true
        offlineSupportDescription = "On-device English recognition available (\(locale.identifier))."
        return true
    }

    func startRecognition(using audioCaptureManager: GlowAudioCaptureManager) throws {
        guard !isRecognizing, recognitionTask == nil else {
            throw GlowSpeechRecognitionError.sessionAlreadyRunning
        }
        guard authorizationStatus == .authorized else {
            throw GlowSpeechRecognitionError.speechPermissionRequired
        }
        guard isOfflineRecognitionAvailable,
              let recognizer,
              recognizer.supportsOnDeviceRecognition else {
            throw GlowSpeechRecognitionError.offlineRecognitionUnavailable
        }
        guard audioCaptureManager.isCapturing else {
            throw GlowSpeechRecognitionError.microphoneNotCapturing
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let sessionID = UUID()
        activeSessionID = sessionID
        self.audioCaptureManager = audioCaptureManager
        recognitionRequest = request
        recognizedText = ""
        onRecognizedTextChanged?(recognizedText)
        isPartialResult = false
        errorMessage = nil
        isStopping = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionUpdate(result: result, error: error, sessionID: sessionID)
            }
        }

        audioCaptureManager.onAudioBuffer = { buffer in
            request.append(buffer)
        }
        isRecognizing = true
    }

    func stopRecognition() {
        guard let recognitionTask else {
            audioCaptureManager?.onAudioBuffer = nil
            return
        }

        isStopping = true
        audioCaptureManager?.onAudioBuffer = nil
        recognitionRequest?.endAudio()
        recognitionTask.finish()
        audioCaptureManager?.stopCapture()
        audioCaptureManager = nil
        isRecognizing = false
    }

    func cancelRecognition() {
        guard let recognitionTask else {
            audioCaptureManager?.onAudioBuffer = nil
            return
        }

        audioCaptureManager?.onAudioBuffer = nil
        audioCaptureManager?.stopCapture()
        recognitionTask.cancel()
        self.audioCaptureManager = nil
        self.recognitionTask = nil
        recognitionRequest = nil
        activeSessionID = nil
        isRecognizing = false
        isPartialResult = false
        isStopping = false
    }

    func clearRecognizedText() {
        recognizedText = ""
        isPartialResult = false
        errorMessage = nil
        onRecognizedTextChanged?(recognizedText)
    }

    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }

        if let result {
            recognizedText = result.bestTranscription.formattedString
            isPartialResult = !result.isFinal
            onRecognizedTextChanged?(recognizedText)
            if result.isFinal {
                isStopping = false
                onRecognitionCompleted?(recognizedText)
                finishSession()
                return
            }
        }

        if let error {
            if isStopping {
                onRecognitionCompleted?(recognizedText)
            } else {
                let message = "Speech recognition failed: \(error.localizedDescription)"
                errorMessage = message
                onRecognitionFailure?(message)
            }
            finishSession()
        }
    }

    private func finishSession() {
        audioCaptureManager?.onAudioBuffer = nil
        audioCaptureManager?.stopCapture()
        audioCaptureManager = nil
        recognitionTask = nil
        recognitionRequest = nil
        activeSessionID = nil
        isRecognizing = false
        isPartialResult = false
        isStopping = false
    }
}

private enum GlowSpeechRecognitionError: LocalizedError {
    case sessionAlreadyRunning
    case speechPermissionRequired
    case offlineRecognitionUnavailable
    case microphoneNotCapturing

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyRunning: "Speech recognition is already running."
        case .speechPermissionRequired: "Speech recognition permission is required."
        case .offlineRecognitionUnavailable: "On-device speech recognition is unavailable for this locale. Network recognition is disabled."
        case .microphoneNotCapturing: "Enable Glow microphone capture before starting speech recognition."
        }
    }
}