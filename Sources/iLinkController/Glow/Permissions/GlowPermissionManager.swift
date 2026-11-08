import AVFoundation
import Combine

@MainActor
final class GlowPermissionManager: ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var statusDescription: String {
        switch authorizationStatus {
        case .authorized: "Microphone access allowed"
        case .denied: "Microphone access denied"
        case .restricted: "Microphone access restricted"
        case .notDetermined: "Microphone access not requested"
        @unknown default: "Microphone access unavailable"
        }
    }

    var permissionExplanation: String? {
        switch authorizationStatus {
        case .denied:
            "Allow microphone access for iLink Controller in System Settings, then try again."
        case .restricted:
            "Microphone access is restricted by macOS or device policy."
        case .notDetermined, .authorized:
            nil
        @unknown default:
            "Microphone access status could not be determined."
        }
    }

    func requestWhenEnablingGlow() async -> AVAuthorizationStatus {
        refreshStatus()
        guard authorizationStatus == .notDetermined else { return authorizationStatus }

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        authorizationStatus = granted ? .authorized : .denied
        return authorizationStatus
    }

    func refreshStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}