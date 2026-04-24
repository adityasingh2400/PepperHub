@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// Wraps SFSpeechRecognizer for live partial transcription with continuous
/// listening — the session stays open until the user taps stop.
///
/// IMPORTANT — Swift 6 isolation:
/// Audio engine and speech recognizer fire callbacks on background queues
/// (`RealtimeMessenger.mServiceQueue`, `com.apple.Speech.Task.Internal`,
/// `com.apple.root.default-qos`). Closures formed inside a `@MainActor`
/// context inherit main-actor isolation and Swift 6 aborts the process when
/// the framework dispatches them off-main. Audio setup therefore happens in
/// `nonisolated` functions; UI mutations hop back to main via `Task { @MainActor }`.
@MainActor
final class VoiceRecognitionService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case denied(String)
        case unsupported(String)
        case error(String)

        var errorMessage: String? {
            switch self {
            case .denied(let m), .unsupported(let m), .error(let m): return m
            default: return nil
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var audioLevel: Float = 0

    nonisolated(unsafe) private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    nonisolated(unsafe) private let audioEngine = AVAudioEngine()
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    nonisolated private static let log = Logger(subsystem: "com.peptideapp.app", category: "voice")

    var isListening: Bool { if case .listening = state { return true } ; return false }

    /// Toggle: tap mic to start, tap again to stop.
    func start(contextualStrings: [String]) async {
        if isListening { stop(); return }

        guard let recognizer else {
            state = .unsupported("Speech recognition isn't available for this language.")
            return
        }
        guard recognizer.isAvailable else {
            state = .unsupported("Speech recognition is temporarily unavailable.")
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
            Self.log.error("beginRecognition failed: \(error.localizedDescription, privacy: .public)")
            state = .error(Self.userFriendly(error))
        }
    }

    func stop() {
        cleanup()
        if case .listening = state { state = .idle }
    }

    /// Wipe any error/state so the UI returns to a fresh "Tap to speak" prompt.
    func clearError() {
        if case .listening = state { return }
        state = .idle
        transcript = ""
    }

    // MARK: - Audio engine setup (nonisolated to keep closures off the main actor)

    nonisolated private func beginRecognition(contextualStrings: [String]) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.contextualStrings = contextualStrings
        // Force server recognition. The simulator's on-device model
        // (mini.json) is broken in many Xcode releases, and even on real
        // devices server recognition is more accurate for short, unusual
        // peptide names like BPC-157, Tirzepatide, etc.
        req.requiresOnDeviceRecognition = false
        req.taskHint = .dictation
        if #available(iOS 16, *) { req.addsPunctuation = false }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        Self.log.info("Starting recognition. Input format: sr=\(format.sampleRate, privacy: .public) ch=\(format.channelCount, privacy: .public)")
        guard format.sampleRate > 0 else {
            throw NSError(
                domain: "VoiceRecognitionService", code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Audio input unavailable. (Check System Settings → Privacy → Microphone.)"]
            )
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let level = Self.peakAmplitude(buffer: buffer)
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        audioEngine.prepare()
        try audioEngine.start()

        let t = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            // Continuous listening: when isFinal fires (silence detected) we
            // keep the engine running and let the next chunk produce a new
            // partial. Only an actual error tears the session down.
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in self?.transcript = text }
            }
            if let error = error as NSError? {
                Self.log.error("recognitionTask error: domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public) msg=\(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cleanup()
                    self.state = .error(Self.userFriendly(error))
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

    // MARK: - Helpers

    /// Convert noisy framework errors into something the user can act on.
    nonisolated private static func userFriendly(_ error: Error) -> String {
        let ns = error as NSError
        let code = ns.code
        let domain = ns.domain
        // Apple Foundation Audio + Siri Understanding both throw under
        // kAFAssistantErrorDomain / kLSRErrorDomain when the on-device model
        // isn't installed or the network request to Apple's servers fails.
        if domain.contains("AFAssistant") || domain.contains("Speech") || domain.contains("LSR") {
            #if targetEnvironment(simulator)
            return "Voice doesn't work reliably in iOS Simulator. Try a real device, or type the compound name below."
            #else
            return "Speech recognition error (\(code)). Check your internet connection and try again."
            #endif
        }
        if domain == NSURLErrorDomain {
            return "Network unavailable. Speech recognition needs internet — try again or type below."
        }
        return ns.localizedDescription
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
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
