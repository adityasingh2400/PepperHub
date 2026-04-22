import AVFoundation
import Foundation
import Speech

/// Wraps SFSpeechRecognizer for live partial transcription.
///
/// IMPORTANT — Swift 6 isolation:
/// The audio engine and speech recognizer call our closures on background queues
/// (`RealtimeMessenger.mServiceQueue`, `com.apple.Speech.Task.Internal`,
/// `com.apple.root.default-qos`). If those closures are formed inside a
/// `@MainActor` context they inherit main-actor isolation, and Swift 6's
/// runtime aborts the process when the framework dispatches them on a
/// non-main queue (`_dispatch_assert_queue_fail`).
///
/// To avoid that we keep the published UI state on `@MainActor` but do all
/// audio/recognition setup from `nonisolated` functions, which produces
/// closures with no actor inheritance.
@MainActor
final class VoiceRecognitionService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case denied(String)
        case unsupported(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var audioLevel: Float = 0

    // Apple-thread-safe types but not Sendable per the type system, so we use
    // nonisolated(unsafe). We only mutate them from start()/stop() which are
    // serialized by the @MainActor on the public API.
    nonisolated(unsafe) private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    nonisolated(unsafe) private let audioEngine = AVAudioEngine()
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    var isListening: Bool { if case .listening = state { return true } ; return false }

    /// Toggle: tap mic to start, tap again to stop.
    func start(contextualStrings: [String]) async {
        if isListening { stop(); return }

        guard let recognizer, recognizer.isAvailable else {
            state = .unsupported("Speech recognition isn't available right now.")
            return
        }

        state = .requestingPermission
        transcript = ""

        let speechAuth = await Self.requestSpeechAuthorization()
        guard speechAuth == .authorized else {
            state = .denied("Enable Speech Recognition in Settings to use voice input.")
            return
        }

        let micGranted = await Self.requestMicrophonePermission()
        guard micGranted else {
            state = .denied("Enable Microphone access in Settings to use voice input.")
            return
        }

        do {
            try beginRecognition(contextualStrings: contextualStrings)
            state = .listening
        } catch {
            cleanup()
            state = .error(error.localizedDescription)
        }
    }

    func stop() {
        cleanup()
        if case .listening = state { state = .idle }
    }

    // MARK: - Audio setup (nonisolated to keep closures off the main actor)

    nonisolated private func beginRecognition(contextualStrings: [String]) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.contextualStrings = contextualStrings
        if #available(iOS 16, *) { req.addsPunctuation = false }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(
                domain: "VoiceRecognitionService", code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Audio input unavailable."]
            )
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // This closure runs on a background audio queue and has NO actor
            // inheritance because we're inside a nonisolated function. Hop to
            // main only for the UI-bound peak amplitude update.
            req.append(buffer)
            let level = Self.peakAmplitude(buffer: buffer)
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        audioEngine.prepare()
        try audioEngine.start()

        let t = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            // Background queue too — same isolation rules.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let transcript { self.transcript = transcript }
                if hasError || isFinal {
                    self.stop()
                }
            }
        }

        request = req
        task = t
    }

    private func cleanup() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Nonisolated permission wrappers
    // TCC fires the callback on com.apple.root.default-qos; if these closures
    // were created in a @MainActor function the runtime would crash on dispatch.

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private nonisolated static func peakAmplitude(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<frames { peak = max(peak, abs(channel[i])) }
        return min(peak * 4, 1)
    }
}
