import AVFoundation
import Combine
import Foundation

private final class GlowAudioBufferRelay {
    private let lock = NSLock()
    private var handler: ((AVAudioPCMBuffer) -> Void)?

    var handlerSnapshot: ((AVAudioPCMBuffer) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    func setHandler(_ handler: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func forward(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let currentHandler = handler
        lock.unlock()
        currentHandler?(buffer)
    }
}

private func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double? {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else { return nil }

    var sumOfSquares: Double = 0
    let sampleCount = frameCount * channelCount

    if let channels = buffer.floatChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = Double(channels[channel][frame])
                sumOfSquares += sample * sample
            }
        }
    } else if let channels = buffer.int16ChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = Double(channels[channel][frame]) / Double(Int16.max)
                sumOfSquares += sample * sample
            }
        }
    } else if let channels = buffer.int32ChannelData {
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = Double(channels[channel][frame]) / Double(Int32.max)
                sumOfSquares += sample * sample
            }
        }
    } else {
        return nil
    }

    let rms = sqrt(sumOfSquares / Double(sampleCount))
    let decibels = 20 * log10(max(rms, 0.000001))
    return min(max((decibels + 60) / 60, 0), 1)
}

@MainActor
final class GlowAudioCaptureManager: ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var audioLevel = 0.0

    var onCaptureFailure: ((String) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioBufferRelay.handlerSnapshot }
        set { audioBufferRelay.setHandler(newValue) }
    }

    private let audioEngine = AVAudioEngine()
    private let audioBufferRelay = GlowAudioBufferRelay()
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw GlowAudioCaptureError.noInputAvailable
        }

        let audioBufferRelay = self.audioBufferRelay
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            audioBufferRelay.forward(buffer)
            guard let level = normalizedLevel(from: buffer) else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleCaptureFailure(GlowAudioCaptureError.unsupportedAudioFormat.localizedDescription)
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isCapturing = true
            observeAudioConfigurationChanges()
        } catch {
            stopCapture()
            throw error
        }
    }

    func stopCapture() {
        removeConfigurationObserver()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        isCapturing = false
        audioLevel = 0
    }

    private func observeAudioConfigurationChanges() {
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCapturing else { return }
                self.handleCaptureFailure("The audio input changed. Disable and re-enable Glow to restart the microphone.")
            }
        }
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    private func handleCaptureFailure(_ message: String) {
        guard isCapturing else { return }
        onCaptureFailure?(message)
        stopCapture()
    }
}

private enum GlowAudioCaptureError: LocalizedError {
    case noInputAvailable
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .noInputAvailable: "No microphone input is available."
        case .unsupportedAudioFormat: "The microphone audio format is not supported."
        }
    }
}