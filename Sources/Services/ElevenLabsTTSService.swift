import AVFoundation
import Foundation

/// Plays Pepper's responses using ElevenLabs TTS.
/// Singleton because only one message should ever be speaking at a time globally.
@MainActor
final class ElevenLabsTTSService: NSObject, ObservableObject {

    static let shared = ElevenLabsTTSService()

    @Published private(set) var playingId: UUID?
    @Published private(set) var loadingId: UUID?
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?

    /// In-memory cache so re-tapping a message doesn't refetch the mp3.
    private var audioCache: [UUID: Data] = [:]

    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        return c
    }())

    private override init() { super.init() }

    /// Speak (or toggle off) a message. Tapping the same id while it's playing stops it.
    func toggle(_ text: String, id: UUID) {
        if playingId == id || loadingId == id {
            stop()
            return
        }
        // Switch from one message to another: cancel the current playback.
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        loadingId = id
        lastError = nil

        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let cached = audioCache[id] {
                    data = cached
                } else {
                    data = try await fetchAudio(for: trimmed)
                    audioCache[id] = data
                }
                if Task.isCancelled { return }
                try beginPlayback(data: data, id: id)
            } catch {
                loadingId = nil
                lastError = (error as NSError).localizedDescription
            }
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        player?.stop()
        player = nil
        loadingId = nil
        playingId = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Internals

    private func beginPlayback(data: Data, id: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)

        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        guard p.play() else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't start audio playback."])
        }
        player = p
        loadingId = nil
        playingId = id
    }

    private func fetchAudio(for text: String) async throws -> Data {
        let voice = APIKeys.elevenLabsVoiceId
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ElevenLabsTTS", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Bad ElevenLabs URL."])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.setValue(APIKeys.elevenLabs, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",            // low-latency model
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.8,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NSError(
                domain: "ElevenLabsTTS",
                code: (resp as? HTTPURLResponse)?.statusCode ?? -3,
                userInfo: [NSLocalizedDescriptionKey: "ElevenLabs error: \(snippet)"]
            )
        }
        return data
    }
}

// MARK: - AVAudioPlayerDelegate

extension ElevenLabsTTSService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let msg = error?.localizedDescription ?? "Audio decode error"
        Task { @MainActor [weak self] in
            self?.lastError = msg
            self?.stop()
        }
    }
}
