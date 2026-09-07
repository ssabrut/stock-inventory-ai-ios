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
///
/// Listening is continuous and self-segmenting: rather than requiring a tap
/// to end each utterance, a silence timer watches for a pause in the live
/// transcript and, once one is detected, cuts a "segment" (calling
/// onSegment) and transparently starts a fresh recognition task so the next
/// utterance begins with a clean transcript — the mic/audio engine itself
/// never stops between segments. This mirrors Siri's own pause-to-advance
/// behavior instead of the old tap-to-stop-per-item flow.
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

    /// Fired once per detected pause with the finalized text of that segment.
    /// Not fired for an empty/whitespace-only segment (e.g. a pause with no
    /// speech since the last segment).
    var onSegment: ((String) -> Void)?

    /// How long the transcript must go unchanged before a segment is cut.
    private let silenceThreshold: TimeInterval = 3.0
    private let silenceCheckInterval: TimeInterval = 0.2

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "id-ID")) ?? SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastObservedTranscript = ""
    private var lastChangeDate = Date()

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

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        // Defensive: a tap can be left installed if startListening() is ever
        // re-entered before a prior stopListening() finished (e.g. a racing
        // auto-start from the Siri refresh callback), and installTap crashes
        // (fatal precondition) if one is already present on this bus.
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening

        startRecognitionTask()
        startSilenceTimer()
    }

    /// Ends the whole listening session (mic + recognition), as opposed to
    /// cutSegment() which only rotates the recognition task between items.
    func stopListening() {
        guard state == .listening else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioLevel = 0
        transcript = ""
        lastObservedTranscript = ""
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecognitionTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        transcript = ""
        lastObservedTranscript = ""
        lastChangeDate = Date()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if let error {
                let nsError = error as NSError
                // Cancelling the task to rotate segments surfaces as an
                // error here too; only treat a *real* failure as fatal.
                guard nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 else {
                    self.state = .failed(error.localizedDescription)
                    return
                }
            }
        }
    }

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForSilence()
        }
    }

    private func checkForSilence() {
        guard state == .listening else { return }

        if transcript != lastObservedTranscript {
            lastObservedTranscript = transcript
            lastChangeDate = Date()
            return
        }

        guard Date().timeIntervalSince(lastChangeDate) >= silenceThreshold else { return }

        let segment = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reset the clock regardless, so an empty/no-speech pause doesn't
        // immediately re-fire every check interval afterward.
        lastChangeDate = Date()

        cutSegment()
        if !segment.isEmpty {
            onSegment?(segment)
        }
    }

    /// Ends the current recognition task and starts a fresh one so the next
    /// utterance's transcript starts clean, without stopping audio capture.
    private func cutSegment() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        startRecognitionTask()
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
