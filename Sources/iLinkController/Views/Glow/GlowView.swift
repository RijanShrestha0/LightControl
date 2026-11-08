import SwiftUI

struct GlowView: View {
    @ObservedObject var assistant: GlowAssistantManager
    @ObservedObject private var permissionManager: GlowPermissionManager
    @ObservedObject private var audioCaptureManager: GlowAudioCaptureManager

    init(assistant: GlowAssistantManager) {
        self.assistant = assistant
        _permissionManager = ObservedObject(wrappedValue: assistant.permissionManager)
        _audioCaptureManager = ObservedObject(wrappedValue: assistant.audioCaptureManager)
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
            }
            .padding(.top, 18)

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
        case .capturingAudio, .ready, .requestingPermission:
            "Disable Glow"
        case .disabled, .error:
            "Enable Glow"
        }
    }

    private var permissionIcon: String {
        permissionManager.authorizationStatus == .authorized ? "checkmark.circle" : "mic.slash"
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
        case .error:
            "Glow could not start or continue audio capture."
        }
    }
}