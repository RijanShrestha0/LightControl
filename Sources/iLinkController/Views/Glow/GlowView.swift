import SwiftUI

struct GlowView: View {
    @ObservedObject var assistant: GlowAssistantManager
    @ObservedObject private var permissionManager: GlowPermissionManager
    @ObservedObject private var audioCaptureManager: GlowAudioCaptureManager
    @ObservedObject private var speechRecognitionManager: GlowSpeechRecognitionManager

    init(assistant: GlowAssistantManager) {
        self.assistant = assistant
        _permissionManager = ObservedObject(wrappedValue: assistant.permissionManager)
        _audioCaptureManager = ObservedObject(wrappedValue: assistant.audioCaptureManager)
        _speechRecognitionManager = ObservedObject(wrappedValue: assistant.speechRecognitionManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text("Glow")
                    .font(.system(size: 28, weight: .medium))
                Text("Your light. Your voice.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 32)

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(assistant.state == .capturingAudio ? 0.08 : 0.035))
                    .frame(width: 164, height: 164)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    .frame(width: 142, height: 142)
                Image(systemName: "mic.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.primary.opacity(assistant.state == .disabled ? 0.45 : 1))
            }
            .accessibilityLabel(assistant.state == .capturingAudio ? "Microphone active" : "Microphone inactive")
            .animation(.easeOut(duration: 0.2), value: assistant.state)

            Text(assistant.state.title)
                .font(.system(size: 16, weight: .medium))
                .padding(.top, 20)

            Text(stateDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("INPUT LEVEL")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text(assistant.state == .capturingAudio ? "LIVE" : "OFF")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: audioCaptureManager.audioLevel)
                    .progressViewStyle(.linear)
                    .tint(.primary)
                    .accessibilityLabel("Microphone input level")
            }
            .frame(maxWidth: 300)
            .padding(.top, 28)

            Button(actionTitle) {
                Task { await assistant.toggle() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(.background)
            .controlSize(.large)
            .disabled(assistant.state == .requestingPermission)
            .padding(.top, 24)

            VStack(spacing: 5) {
                Label(permissionManager.statusDescription, systemImage: permissionIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Label(speechRecognitionManager.authorizationDescription, systemImage: speechPermissionIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let explanation = permissionManager.permissionExplanation {
                    Text(explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                if let errorMessage = assistant.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .textSelection(.enabled)
                }
                if let errorMessage = speechRecognitionManager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 18)

            Text(speechRecognitionManager.offlineSupportDescription)
                .font(.system(size: 11))
                .foregroundStyle(speechRecognitionManager.isOfflineRecognitionAvailable ? .secondary : .tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            if speechRecognitionManager.isRecognizing {
                Button("Stop Listening", systemImage: "stop.fill") {
                    assistant.stopSpeechRecognition()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, 16)
            } else {
                Button("Start Listening", systemImage: "waveform") {
                    Task { await assistant.startSpeechRecognition() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSpeechSetupInProgress)
                .padding(.top, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(speechRecognitionManager.isPartialResult ? "LIVE TRANSCRIPTION" : "RECOGNIZED TEXT")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if !speechRecognitionManager.recognizedText.isEmpty {
                        Button("Clear Text", systemImage: "xmark.circle") {
                            assistant.clearRecognizedText()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                Text(speechRecognitionManager.recognizedText.isEmpty ? "Recognized speech will appear here." : speechRecognitionManager.recognizedText)
                    .font(.system(size: 13))
                    .foregroundStyle(speechRecognitionManager.recognizedText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                Divider()
                HStack {
                    Text("LOCAL COMMAND INTERPRETATION")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if speechRecognitionManager.isPartialResult {
                        Text("PROVISIONAL")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(assistant.interpretedCommand.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text("Interpretation only. No command is executed.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .frame(maxWidth: 440)
            .padding(.top, 20)

            Spacer(minLength: 24)

            Text("Audio is processed in memory for level display and immediately discarded. No recordings are saved or uploaded.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .onDisappear {
            assistant.disable()
        }
    }

    private var actionTitle: String {
        switch assistant.state {
        case .capturingAudio, .ready, .requestingPermission, .requestingSpeechPermission,
             .checkingOfflineSupport, .recognizingSpeech:
            "Disable Glow"
        case .disabled, .recognitionCompleted, .recognitionUnavailable, .error:
            "Enable Glow"
        }
    }

    private var isSpeechSetupInProgress: Bool {
        assistant.state == .requestingPermission
            || assistant.state == .requestingSpeechPermission
            || assistant.state == .checkingOfflineSupport
    }

    private var permissionIcon: String {
        permissionManager.authorizationStatus == .authorized ? "checkmark.circle" : "mic.slash"
    }

    private var speechPermissionIcon: String {
        speechRecognitionManager.authorizationStatus == .authorized ? "checkmark.circle" : "text.bubble"
    }

    private var stateDescription: String {
        switch assistant.state {
        case .disabled:
            "Glow is off. Enable it to request microphone access and start local audio metering."
        case .requestingPermission:
            "Waiting for microphone authorization."
        case .ready:
            "Microphone permission is available. Starting audio capture."
        case .capturingAudio:
            "Audio metering is active. Wake-word detection is not enabled in this phase."
        case .requestingSpeechPermission:
            "Waiting for permission to recognize speech."
        case .checkingOfflineSupport:
            "Checking that this locale can be recognized entirely on this Mac."
        case .recognizingSpeech:
            "Transcribing locally. Recognized text is not sent to Bluetooth or executed."
        case .recognitionCompleted:
            "Recognition stopped. You can review or clear the text above."
        case .recognitionUnavailable:
            "Local speech recognition is unavailable. Glow will not use network recognition."
        case .error:
            "Glow could not start or continue audio capture."
        }
    }
}