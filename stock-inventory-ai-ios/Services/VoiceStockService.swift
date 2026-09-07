//
//  VoiceStockService.swift
//  stock-inventory-ai-ios
//

import AVFoundation
import Speech

/// Drives on-device speech-to-text for the in-app custom recording UI
/// (StockSessionOverlay's floating FAB). Separate from AddStockIntent's Siri flow, which runs
/// out-of-process and can't host custom UI — this gives the app its own
/// mic button + live transcript + waveform instead of Siri's fixed surface.
@Observable
final class VoiceStockService {
    enum State: Equatable {
        case idle
        case listening
        case denied
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript: String = ""
    /// Rolling input level (0...1) for driving a waveform/level meter while listening.
    private(set) var audioLevel: Double = 0

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID")) ?? SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            state = .denied
            return false
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            state = .denied
            return false
        }

        return true
    }

    func startListening() throws {
        guard state != .listening else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.stopListening()
            }
        }
    }

    func stopListening() {
        guard state == .listening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        audioLevel = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frameCount))
        // RMS for speech-level audio sits well under 1.0, so scale up before
        // clamping to give the meter visible motion at normal talking volume.
        let level = Double(min(max(rms * 12, 0), 1))

        Task { @MainActor [weak self] in
            self?.audioLevel = level
        }
    }
}
