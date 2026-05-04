import SwiftUI
import SwiftData
import UIKit

/// Hardware-accurate screen metrics. iOS knows the exact physical corner
/// radius of every device's display — Apple exposes it internally via
/// `UIScreen._displayCornerRadius`. We read it via KVC so our overlay ring
/// traces the real rounded rectangle of the screen, not a best-guess value.
/// If the key ever stops working in a future iOS, we fall back to a per-device
/// table keyed off screen size.
enum DeviceScreenMetrics {
    static var displayCornerRadius: CGFloat {
        let key = ["Radius", "Corner", "display", "_"].reversed().joined()
        if let value = UIScreen.main.value(forKey: key) as? CGFloat, value > 0 {
            return value
        }
        return fallbackCornerRadius(for: UIScreen.main.bounds.size)
    }

    /// Live home-indicator / bottom safe-area inset in points. Reads from the
    /// active key window so it's accurate regardless of SwiftUI layout
    /// context (works even inside `.ignoresSafeArea` containers).
    static var homeIndicatorInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }

    /// Best-known device display corner radii in points, keyed by screen size.
    /// Values are from Apple's published device specs / AppleVisualEffectView
    /// measurements. Covers modern notch + Dynamic Island iPhones.
    private static func fallbackCornerRadius(for size: CGSize) -> CGFloat {
        let h = max(size.width, size.height)
        switch h {
        case 956: return 55   // iPhone 15/16 Pro Max, 17 Pro Max
        case 932: return 55   // iPhone 14 Pro Max, 15/16 Plus
        case 874: return 55   // iPhone 16 Pro
        case 852: return 55   // iPhone 14 Pro, 15/16
        case 844: return 47.33 // iPhone 14, 13, 12
        case 926: return 53.33 // iPhone 14 Plus, 13 Pro Max, 12 Pro Max
        case 896: return 39   // iPhone 11, XR, XS Max
        case 812: return 39   // iPhone X, XS, 11 Pro, 12 mini, 13 mini
        default:
            if h >= 812 { return 47 }
            return 0 // Home-button devices have square screens
        }
    }
}

/// Non-modal voice navigator. Tapping the mic keeps the app visible, traces a
/// maroon perimeter from the floating voice button, then lets Pepper navigate
/// behind the glow.
struct VoiceNavigatorView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pepperService: PepperService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var voice = VoiceRecognitionService()
    @ObservedObject private var tts = ElevenLabsTTSService.shared

    @State private var traceProgress: CGFloat = 0
    @State private var glowSettled = false
    @State private var completionRipple = false
    @State private var ttsId = UUID()
    @State private var sentMessageStartIndex = 0
    @State private var spokenMessageIndex: Int? = nil
    @State private var phase: Phase = .listening
    @State private var autoSubmitTask: Task<Void, Never>? = nil
    @State private var closeTask: Task<Void, Never>? = nil
    /// True while the exit animation is playing — drives `PepperFaceView` to
    /// run its activation in reverse before we actually unmount.
    @State private var closing = false
    /// Most-recent router decision. Lets `scheduleAutoSubmit` fire early on
    /// high-confidence partial transcripts without requiring a 1 s silence
    /// wait, and lets `submitTranscript` skip the Claude round-trip entirely
    /// when a concrete navigational intent already resolved.
    @State private var routedCommand: VoiceCommand? = nil
    @State private var hasSubmitted = false
    /// Active disambiguation group — when set, we render the pop-out
    /// chooser and wait for the user's tap instead of closing the overlay.
    @State private var pendingDisambiguation: (group: DisambiguationGroup, action: VoiceAction)? = nil

    enum Phase { case listening, thinking, speaking }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Perimeter ring fills the entire screen including under the
            // home-indicator safe area — it traces the physical display edge.
            GeometryReader { proxy in
                let voiceCenter = voiceButtonCenter(
                    in: proxy.size,
                    bottomInset: DeviceScreenMetrics.homeIndicatorInset
                )
                let cornerRadius = DeviceScreenMetrics.displayCornerRadius
                ZStack {
                    VoicePerimeterGlow(
                        progress: traceProgress,
                        isSettled: glowSettled,
                        showRipple: completionRipple,
                        audioLevel: CGFloat(voice.audioLevel),
                        sourcePoint: voiceCenter,
                        sourceYRatio: voiceCenter.y / max(proxy.size.height, 1),
                        cornerRadius: cornerRadius
                    )
                    .allowsHitTesting(false)

                    // Disambiguation chooser — lives in the same geometry
                    // reader so the bubbles can emerge from the real voice
                    // button center + target layout in absolute points.
                    if let pending = pendingDisambiguation {
                        VoiceDisambiguationView(
                            group: pending.group,
                            voiceButtonCenter: voiceCenter,
                            containerSize: proxy.size,
                            onPick: { option in
                                handleDisambiguationPick(option, action: pending.action)
                            }
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Button + caption live in the normal safe-area coordinate space
            // so their bottom anchor matches MainTabView's floating button
            // pixel-for-pixel. No manual inset math, no layout drift.
            if let text = captionText {
                VoiceCaptionPill(text: text)
                    .padding(.trailing, 18)
                    .padding(.bottom, 176)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // Pepper face replaces the MainTabView bubble pixel-for-pixel.
            // The face is 72×72 whereas the resting bubble is 56×56, so we
            // pad by 102 (= 110 bubble padding − (72−56)/2 size offset − 0)
            // to land the face center exactly where the bubble center was.
            voiceControlButton
                .padding(.trailing, 16)
                .padding(.bottom, 102)
        }
        .task {
            sentMessageStartIndex = pepperService.messages.count
            Task { await voice.start(contextualStrings: navigationVocabulary()) }
            try? await Task.sleep(nanoseconds: 70_000_000)
            startPerimeterAnimation()
        }
        .onDisappear {
            autoSubmitTask?.cancel()
            closeTask?.cancel()
            voice.stop()
            // TTS is disabled in the voice navigator (see executeNavCommand /
            // handleDisambiguationPick — navigation is silent). Still call
            // stop() defensively in case `AskPepperView` left something
            // playing from a different surface.
            tts.stop()
        }
        .onChange(of: voice.transcript) { _, newValue in
            scheduleAutoSubmit(for: newValue)
        }
        .onChange(of: pepperService.messages.count) { _, _ in
            handlePepperResponseIfNeeded()
        }
        .onChange(of: pepperService.messages.last?.text ?? "") { _, _ in
            handlePepperResponseIfNeeded()
        }
        .onChange(of: pepperService.isStreaming) { _, _ in
            handlePepperResponseIfNeeded()
        }
        .onChange(of: pepperService.pendingToolCall?.id) { _, newValue in
            if newValue != nil {
                nav.presentPepper()
                closeAfterCompletion(delay: 0.15)
            }
        }
        .onChange(of: voice.state.errorMessage ?? "") { _, newValue in
            // Speech-recognition errors (most commonly `kAFAssistantErrorDomain`
            // code 1110 — "check your internet") used to surface as a caption
            // pill on top of the app, which looked broken even though voice
            // was technically working. Now we swallow them: if we never
            // resolved a command, just close the overlay quietly. The user
            // can tap the mic again to retry.
            guard !newValue.isEmpty else { return }
            // If a command already submitted (e.g. nav is in flight), ignore
            // the trailing error. Otherwise bail out gracefully.
            if !hasSubmitted && pendingDisambiguation == nil {
                closeNow(stopSpeech: true)
            }
        }
    }

    private var voiceControlButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if phase == .listening {
                submitTranscript()
            } else {
                closeNow()
            }
        } label: {
            PepperFaceView(
                phase: phase,
                micLevel: CGFloat(voice.audioLevel),
                playbackLevel: CGFloat(tts.playbackLevel),
                settled: glowSettled,
                closing: closing
            )
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Voice assistant")
        .accessibilityHint(phase == .listening ? "Tap to submit." : "Tap to cancel.")
    }

    private var captionText: String? {
        // Suppress recognition error surfacing — voice nav is input-only,
        // errors just mean "try again". The onChange handler closes the
        // overlay; no reason to flash "Speech recognition error (1110)".
        if pendingDisambiguation != nil { return nil /* chooser has its own title */ }
        let transcript = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        switch phase {
        case .listening:
            return transcript.isEmpty ? nil : "\"\(transcript)\""
        case .thinking:
            return "Navigating…"
        case .speaking:
            // Voice nav is silent now — the `.speaking` phase is kept
            // internally to drive the close sequence but shouldn't show a
            // "Done" pill since there's nothing being spoken.
            return nil
        }
    }

    private func voiceButtonCenter(in size: CGSize, bottomInset: CGFloat) -> CGPoint {
        // Must match MainTabView's PepperBubbleButton resting center:
        // bubble sits at `padding(.bottom, 110)` with 56 pt diameter, so
        // its center is 138 pt above the safe-area bottom + home-indicator
        // inset. The ring glow emerges from exactly this point.
        CGPoint(x: size.width - 44, y: size.height - 138 - bottomInset)
    }

    private func startPerimeterAnimation() {
        traceProgress = 0
        glowSettled = false
        completionRipple = false
        withAnimation(.timingCurve(0.18, 0.82, 0.22, 1.0, duration: 0.9)) {
            traceProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            glowSettled = true
            completionRipple = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                completionRipple = false
            }
        }
    }

    // MARK: - Submit transcript
    //
    // Perf note: the old flow waited **1,150 ms of silence** after any
    // partial transcript, then shipped everything to Claude via Supabase
    // (1–3 s round-trip), then called ElevenLabs (another 400–1000 ms)
    // before the user heard anything. End-to-end: ~2.5–5 seconds.
    //
    // New flow:
    //   1. Every partial transcript is routed through `VoiceCommandRouter`
    //      synchronously (≈1 ms).
    //   2. High-confidence intents (≥0.9) fire **immediately** — no wait.
    //      "Open Research" hits the new tab before the user stops talking.
    //   3. Medium-confidence (0.8–0.9) fire after a tight 300 ms dwell —
    //      just long enough to let the user continue ("BPC-157… dosing").
    //   4. Only unresolved transcripts wait the full 900 ms and go to Claude.
    //   5. Navigational intents skip Claude entirely — they just drive
    //      `NavigationCoordinator` and play a prerecorded TTS phrase.

    private func scheduleAutoSubmit(for transcript: String) {
        guard phase == .listening else { return }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        autoSubmitTask?.cancel()
        guard trimmed.count > 1 else { return }

        let command = VoiceCommandRouter.route(trimmed)
        routedCommand = command

        // Fire-early ladder based on confidence. The dwell is measured from
        // the last partial transcript change, so rapid updates keep
        // cancelling and re-arming — we only submit once the user has
        // paused.
        let dwellNs: UInt64 = {
            guard let c = command else { return 900_000_000 }
            switch c.confidence {
            case 0.9...:  return 80_000_000   // essentially immediate
            case 0.8..<0.9: return 320_000_000
            case 0.6..<0.8: return 600_000_000
            default:        return 900_000_000
            }
        }()

        autoSubmitTask = Task {
            try? await Task.sleep(nanoseconds: dwellNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                let current = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if phase == .listening && current == trimmed {
                    submitTranscript()
                }
            }
        }
    }

    private func submitTranscript() {
        guard phase == .listening, !hasSubmitted else { return }
        autoSubmitTask?.cancel()
        let trimmed = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.stop()

        guard !trimmed.isEmpty else {
            closeNow()
            return
        }

        // Prefer the most recent router decision, but re-route on the final
        // transcript in case the partial we captured earlier was stale.
        let command = VoiceCommandRouter.route(trimmed) ?? routedCommand
        hasSubmitted = true

        // ── Navigational intent: local-only, no LLM, prerecorded audio ─
        if let cmd = command, cmd.isNavigational {
            executeNavCommand(cmd)
            return
        }

        // ── Ask-Pepper fallback: only when really open-ended ───────────
        guard let userId = authManager.session?.user.id.uuidString else {
            closeNow()
            return
        }
        phase = .thinking
        sentMessageStartIndex = pepperService.messages.count
        Task {
            await pepperService.send(userMessage: trimmed, modelContext: modelContext, userId: userId)
            await MainActor.run { handlePepperResponseIfNeeded() }
        }
    }

    /// Executes a fully-resolved navigational command **silently** and
    /// immediately tears down the overlay. No TTS — the UI itself is the
    /// feedback channel (tab switch, walkthrough animation, spotlight
    /// rings). This is the "voice off" design: mic for input, pixels for
    /// output. Bypasses all audio latency and the 1110 "check your
    /// internet" errors that used to surface when ElevenLabs/SFSpeech
    /// hiccupped.
    private func executeNavCommand(_ cmd: VoiceCommand) {
        applyNavigation(cmd)

        // For disambiguation, the overlay intentionally stays open — the
        // chooser needs to be visible for the user to tap. For every other
        // nav intent, fade the ring immediately so the user sees the new
        // screen without a maroon halo lingering on top.
        if case .disambiguate = cmd.kind { return }
        closeAfterCompletion(delay: navCloseDelay(for: cmd))
    }

    /// How long to leave the ring visible after navigation fires. Shorter
    /// for instant nav (tab switch), slightly longer for the research
    /// walkthrough so the user registers "something animated, and now I'm
    /// here" before the ring disappears. Still well under what the old
    /// TTS-driven flow used (the ring used to hang around for ≥2 s).
    private func navCloseDelay(for cmd: VoiceCommand) -> TimeInterval {
        switch cmd.kind {
        case .openCompound:
            // Research walkthrough takes ~760 ms to land on the detail
            // page; start the ring fade at ~250 ms so it completes right
            // as the final step animates in.
            return 0.25
        case .disambiguate:
            return 0
        case .openInjectionTracker, .logDose:
            // Sheet animation is ~300 ms; match it.
            return 0.2
        case .openTab, .askPepper, .unknown:
            return 0.12
        }
    }

    private func applyNavigation(_ cmd: VoiceCommand) {
        switch cmd.kind {
        case .openTab(let tab):
            nav.switchTab(tab)
        case .openCompound(let compound, let action):
            nav.voiceOpenCompound(compound, action: action)
        case .openInjectionTracker:
            nav.presentInjectionTracker()
        case .logDose:
            nav.presentQuickDoseLog()
        case .disambiguate(let group, let action):
            // Switch to Research tab so the walkthrough lands in the right
            // place when the user picks a bubble.
            nav.switchTab(.research)
            withAnimation(.easeOut(duration: 0.2)) {
                pendingDisambiguation = (group: group, action: action)
            }
        case .askPepper, .unknown:
            break
        }
    }

    /// User tapped a bubble — resolve it to a real compound, fire the
    /// walkthrough, and fade the overlay. No TTS confirmation.
    private func handleDisambiguationPick(_ option: DisambiguationGroup.Option, action: VoiceAction) {
        let compound: Compound = {
            switch option.resolution {
            case .compound(let c): return c
            case .blend(let primary, _): return primary
            }
        }()

        pendingDisambiguation = nil
        nav.voiceOpenCompound(compound, action: action)

        // Close once the family card spotlight has had time to pulse and
        // the list view has pushed. The walkthrough continues beneath the
        // fading overlay — feels like Pepper handed off and got out of the way.
        closeAfterCompletion(delay: 0.35)
    }

    /// Pepper (free-form Q&A) response handling. With voice disabled, we
    /// no longer TTS the reply — we just close the overlay and rely on the
    /// chat thread showing in AskPepper for follow-up. Kept as a function
    /// instead of deleted so the onChange hooks still have something to
    /// call and the "thinking" phase can resolve.
    private func handlePepperResponseIfNeeded() {
        if pepperService.pendingToolCall != nil {
            nav.presentPepper()
            closeAfterCompletion(delay: 0.15)
            return
        }
        guard phase == .thinking else { return }
        guard !pepperService.isStreaming else { return }
        guard let lastIdx = pepperService.messages.indices.last(where: { idx in
            idx > sentMessageStartIndex &&
            !pepperService.messages[idx].isUser &&
            !pepperService.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return }
        guard spokenMessageIndex != lastIdx else { return }

        spokenMessageIndex = lastIdx
        // Open the Pepper chat surface so the user can read the reply,
        // rather than silently throwing away the response.
        nav.presentPepper()
        closeAfterCompletion(delay: 0.15)
    }

    private func closeAfterCompletion(delay: TimeInterval) {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { closeNow(stopSpeech: false) }
        }
    }

    private func closeNow(stopSpeech: Bool = true) {
        autoSubmitTask?.cancel()
        closeTask?.cancel()
        voice.stop()
        if stopSpeech { tts.stop() }
        // Guard against double-invocation while the exit animation is
        // already running.
        guard !closing else { return }
        // Reverse the activation animation: eyes collapse back into one
        // pepper, dark wine eases back to light wine, mouth fades out.
        // With voice disabled the nav overlay should get out of the user's
        // way fast — 240 ms face collapse + 180 ms ring fade = ~420 ms
        // total vs. the old 640 ms when TTS playback drove the timing.
        withAnimation(.easeOut(duration: 0.24)) {
            closing = true
        }
        // Fade the whole overlay (perimeter ring + caption) a beat later so
        // the pepper has time to finish collapsing before it disappears.
        closeTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    nav.dismissVoiceNavigator()
                }
            }
        }
    }

    private func navigationVocabulary() -> [String] {
        var v = CompoundCatalog.speechVocabulary
        v.append(contentsOf: [
            "Today", "Food", "Protocol", "Stack", "Track", "Research",
            "open", "go to", "show me", "calculator", "calculate",
            "pinning protocol", "injection site tracker", "site tracker",
            "site rotation", "log a dose", "log dose",
            "ask pepper", "where do I inject"
        ])
        return v
    }
}

private struct VoicePerimeterGlow: View {
    let progress: CGFloat
    let isSettled: Bool
    let showRipple: Bool
    let audioLevel: CGFloat
    let sourcePoint: CGPoint
    let sourceYRatio: CGFloat
    let cornerRadius: CGFloat
    var flowEnabled = true

    @State private var flowPhase = false

    var body: some View {
        ZStack {
            // Soft outer halo — wide blurred maroon bloom
            perimeter(progress)
                .stroke(Color(hex: "9f1239").opacity(0.55), style: StrokeStyle(lineWidth: 38, lineCap: .round, lineJoin: .round))
                .blur(radius: 22 + audioLevel * 16)
                .opacity(isSettled ? 0.95 : 0.8)

            // Core ring — deep maroon body with subtle luminance shifts only
            // within the maroon family. No cream, no off-hue highlights: the
            // motion reads as fluid dark pigment, not a candy stripe.
            perimeter(progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "5a0018"),
                            Color(hex: "7a0026"),
                            Color(hex: "b00f42"),
                            Color(hex: "d32359"),
                            Color(hex: "b00f42"),
                            Color(hex: "7a0026"),
                            Color(hex: "5a0018")
                        ],
                        center: .center,
                        angle: .degrees(flowPhase ? 360 : 0)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Color(hex: "9f1239").opacity(0.9), radius: isSettled ? 24 + audioLevel * 18 : 10)

            if isSettled {
                // Counter-rotating inner pigment layer — adds fluid motion
                // without introducing a second hue. Same maroon family, lower
                // alpha, opposite direction.
                perimeter(1)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(hex: "8a0a30").opacity(0.0),
                                Color(hex: "c01a4e").opacity(0.55),
                                Color(hex: "e63a6e").opacity(0.7),
                                Color(hex: "c01a4e").opacity(0.55),
                                Color(hex: "8a0a30").opacity(0.0)
                            ],
                            center: .center,
                            angle: .degrees(flowPhase ? -240 : 120)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 1.2)
                    .blendMode(.plusLighter)
                    .mask(
                        perimeter(1)
                            .stroke(style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    )

                // Bright maroon "comet" highlight that travels the ring.
                // Replaces the previous cream sweep with a hot-pink-maroon
                // that stays in the same hue family.
                perimeter(1)
                    .stroke(
                        AngularGradient(
                            colors: [
                                .clear,
                                Color(hex: "ff5c8a").opacity(0.0),
                                Color(hex: "ff4d85").opacity(0.85),
                                Color(hex: "ff5c8a").opacity(0.0),
                                .clear
                            ],
                            center: .center,
                            angle: .degrees(flowPhase ? 620 : 260)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 2.2)
                    .blendMode(.plusLighter)
                    .mask(
                        perimeter(1)
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                    )

                // Deep inner edge keeps the ring feeling thick and liquid.
                perimeter(1)
                    .stroke(Color(hex: "3a000f").opacity(0.78), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }

            // Completion ripple — always present so there's no
            // insertion/removal transition. Scale + opacity animate in place
            // around `sourcePoint` so the pulse grows at the mic, not across
            // the whole container.
            Circle()
                .stroke(Color(hex: "9f1239").opacity(0.75), lineWidth: 2.5)
                .frame(width: 76, height: 76)
                .scaleEffect(showRipple ? 1.0 : 0.2)
                .opacity(showRipple ? 0.0 : 0.9)
                .position(sourcePoint)
                .animation(.easeOut(duration: 0.42), value: showRipple)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.18), value: audioLevel)
        .drawingGroup()
        .onAppear {
            guard flowEnabled else {
                flowPhase = true
                return
            }
            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                flowPhase = true
            }
        }
    }

    private func perimeter(_ progress: CGFloat) -> VoicePerimeterShape {
        VoicePerimeterShape(progress: progress, sourceYRatio: sourceYRatio, cornerRadius: cornerRadius)
    }
}

private struct VoicePerimeterShape: Shape {
    var progress: CGFloat
    var sourceYRatio: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, sourceYRatio) }
        set {
            progress = newValue.first
            sourceYRatio = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Inset by half the stroke so the ring visually sits inside the screen
        // edge, not clipped. The shape traces the actual device display corner
        // radius (hardware-accurate) so it hugs the real rounded-rectangle
        // perimeter of the screen.
        let strokePadding: CGFloat = 1.0
        let bounds = rect.insetBy(dx: strokePadding, dy: strokePadding)
        // Device corner radius is measured from the physical screen edge. Since
        // we inset slightly, reduce the radius by the same amount so the arc
        // still matches the curve visually.
        let r = max(cornerRadius - strokePadding, 8)
        let sourceY = min(
            max(bounds.minY + bounds.height * sourceYRatio, bounds.minY + r),
            bounds.maxY - r
        )

        var path = Path()
        path.move(to: CGPoint(x: bounds.maxX, y: sourceY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX - r, y: bounds.maxY),
            control: CGPoint(x: bounds.maxX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.minX + r, y: bounds.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX, y: bounds.maxY - r),
            control: CGPoint(x: bounds.minX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + r, y: bounds.minY),
            control: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX - r, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + r),
            control: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: sourceY))

        return path.trimmedPath(from: 0, to: min(max(progress, 0), 1))
    }
}

// MARK: - Pepper face (active voice state)

/// The voice navigator's interactive icon. Starts as a single pepper logo in
/// light wine, then on appear smoothly transitions to dark wine while rotating
/// 45° clockwise and cloning into two mirrored "eyes". An amino-acid chain
/// "mouth" draws between the eyes and reacts to live audio amplitude while
/// listening.
private struct PepperFaceView: View {
    let phase: VoiceNavigatorView.Phase
    let micLevel: CGFloat
    let playbackLevel: CGFloat
    let settled: Bool
    let closing: Bool

    @State private var activated = false

    // Palette — idle light wine matches the MainTabView button so the
    // color transition starts seamlessly from the same shade. Dark wine
    // matches the research card gradient (`#5a1528` / `#3d0d1a`).
    private let lightWine = Color(hex: "9f1239")
    private let darkWine = Color(hex: "5a1528")
    private let deepWine = Color(hex: "3d0d1a")

    // Target geometry for the "eyes" once activated. Values are fractions of
    // the 72×72 container — keeps the face readable on any surrounding frame.
    private let eyeSize: CGFloat = 26
    private let eyeOffsetX: CGFloat = 14
    private let eyeOffsetY: CGFloat = -6

    /// True only when fully active: has been activated AND is not closing.
    /// Used to drive every activated state uniformly, so when `closing`
    /// flips, *all* activated properties animate back in sync.
    private var isActive: Bool { activated && !closing }

    /// The audio level the mouth should react to, depending on phase.
    /// Listening → mic input; speaking → TTS output; thinking → none.
    private var mouthLevel: CGFloat {
        switch phase {
        case .listening: return micLevel
        case .speaking:  return playbackLevel
        case .thinking:  return 0
        }
    }

    var body: some View {
        ZStack {
            // Wine disc background — transitions light → dark on activation,
            // and back on close.
            Circle()
                .fill(isActive ? darkWine : lightWine)
                .shadow(
                    color: (isActive ? deepWine : lightWine).opacity(0.7),
                    radius: isActive ? 18 : 14,
                    y: 6
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(settled && isActive ? 0.28 : 0.12), lineWidth: 1)
                )
                .scaleEffect(pulseScale)
                .animation(.easeInOut(duration: 0.45), value: isActive)

            // Eyes: two mirrored peppers that emerge from the center on
            // activation and collapse back into one on close.
            ZStack {
                pepperIcon
                    .rotationEffect(.degrees(isActive ? -45 : 0))
                    .offset(x: isActive ? -eyeOffsetX : 0, y: isActive ? eyeOffsetY : 0)
                pepperIcon
                    .scaleEffect(x: -1, y: 1) // mirror for right eye
                    .rotationEffect(.degrees(isActive ? 45 : 0))
                    .offset(x: isActive ? eyeOffsetX : 0, y: isActive ? eyeOffsetY : 0)
                    .opacity(isActive ? 1 : 0)
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: isActive)

            // Amino-acid chain mouth — draws between the eyes while active.
            // Uses mic level while listening, TTS level while speaking, so it
            // actually moves when Pepper talks.
            AminoAcidMouth(
                audioLevel: mouthLevel,
                isThinking: phase == .thinking
            )
            .frame(width: 36, height: 14)
            .offset(y: 16)
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isActive ? 1 : 0.75)
            .animation(.easeInOut(duration: 0.32), value: isActive)
        }
        .frame(width: 72, height: 72)
        .onAppear {
            // Kick the activation animation on the next runloop so the color
            // transition and eye split happen smoothly after the view mounts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    activated = true
                }
            }
        }
    }

    private var pepperIcon: some View {
        Image("PepperLogo")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: isActive ? eyeSize : 34, height: isActive ? eyeSize : 34)
            .foregroundColor(.white)
    }

    // Subtle amplitude-driven pulse on the disc — tighter than the old
    // bouncy thinking scale so it reads as breathing, not bouncing.
    private var pulseScale: CGFloat {
        guard isActive else { return 1.0 }
        switch phase {
        case .listening: return 1.0 + min(max(micLevel, 0), 1) * 0.06
        case .speaking:  return 1.0 + min(max(playbackLevel, 0), 1) * 0.05
        case .thinking:  return 1.04
        }
    }
}

/// Amino-acid-chain mouth: alternating C-alpha nodes (filled circles) joined
/// by peptide bonds (straight segments). Reacts to voice amplitude — the
/// chain stretches horizontally and the nodes scale up on loud syllables.
/// `audioLevel` is a pre-selected signal (mic while listening, TTS output
/// while speaking) so this view doesn't need to know the phase.
private struct AminoAcidMouth: View {
    let audioLevel: CGFloat
    let isThinking: Bool

    @State private var flowPhase: CGFloat = 0

    private let nodeCount = 5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let level = min(max(audioLevel, 0), 1)
            // Spread nodes across width; amplitude nudges them outward slightly.
            let stretch = 1.0 + level * 0.15
            // During thinking we want a gentle continuous wave even with no
            // audio, so clamp amplitude to a small floor. Otherwise use the
            // live audio level.
            let floor: CGFloat = isThinking ? 0.25 : 0
            let ampLevel = max(level, floor)
            let amp = h * 0.4 * ampLevel
            let step = (w * stretch) / CGFloat(nodeCount - 1)
            let startX = (w - step * CGFloat(nodeCount - 1)) / 2

            ZStack {
                // Peptide bonds (line segments between C-alpha nodes).
                Path { path in
                    for i in 0..<nodeCount - 1 {
                        let x1 = startX + step * CGFloat(i)
                        let x2 = startX + step * CGFloat(i + 1)
                        let phase1 = flowPhase + CGFloat(i) * 0.9
                        let phase2 = flowPhase + CGFloat(i + 1) * 0.9
                        let y1 = h / 2 + sin(phase1) * amp
                        let y2 = h / 2 + sin(phase2) * amp
                        path.move(to: CGPoint(x: x1, y: y1))
                        path.addLine(to: CGPoint(x: x2, y: y2))
                    }
                }
                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                // C-alpha nodes — slightly larger on amplitude spikes.
                ForEach(0..<nodeCount, id: \.self) { i in
                    let x = startX + step * CGFloat(i)
                    let phase = flowPhase + CGFloat(i) * 0.9
                    let y = h / 2 + sin(phase) * amp
                    let isBackbone = i % 2 == 0
                    Circle()
                        .fill(Color.white)
                        .frame(
                            width: isBackbone ? 5.2 + level * 1.8 : 3.6 + level * 1.2,
                            height: isBackbone ? 5.2 + level * 1.8 : 3.6 + level * 1.2
                        )
                        .position(x: x, y: y)
                }

                // Side-chain stubs off the even nodes — makes it read as
                // "amino acid" rather than a plain dotted line.
                ForEach(0..<nodeCount, id: \.self) { i in
                    if i % 2 == 0 {
                        let x = startX + step * CGFloat(i)
                        let phase = flowPhase + CGFloat(i) * 0.9
                        let y = h / 2 + sin(phase) * amp
                        Path { p in
                            p.move(to: CGPoint(x: x, y: y))
                            p.addLine(to: CGPoint(x: x, y: y - 4.5 - level * 2))
                        }
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 2.4, height: 2.4)
                            .position(x: x, y: y - 5.8 - level * 2)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: audioLevel)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                flowPhase = .pi * 2
            }
        }
    }
}

struct VoiceNavigatorPrewarmView: View {
    var body: some View {
        GeometryReader { proxy in
            let sourcePoint = CGPoint(
                x: proxy.size.width - 44,
                y: proxy.size.height - 138 - DeviceScreenMetrics.homeIndicatorInset
            )
            VoicePerimeterGlow(
                progress: 1,
                isSettled: true,
                showRipple: false,
                audioLevel: 0,
                sourcePoint: sourcePoint,
                sourceYRatio: sourcePoint.y / max(proxy.size.height, 1),
                cornerRadius: DeviceScreenMetrics.displayCornerRadius,
                flowEnabled: false
            )
            .opacity(0.001)
        }
        .ignoresSafeArea()
    }
}

private struct VoiceCaptionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color.appTextPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 240, alignment: .trailing)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(hex: "9f1239").opacity(0.28), lineWidth: 1))
            .shadow(color: Color(hex: "9f1239").opacity(0.22), radius: 16, y: 8)
    }
}

extension Notification.Name {
    static let pepperSeedPrompt = Notification.Name("pepper.seedPrompt")
}

/// Floating mic that summons the voice navigator. Sits next to the Pepper
/// bubble in `MainTabView`. Smaller than the Pepper bubble on purpose — it's
/// a secondary action, so the visual weight tilts toward "ask Pepper".
struct FloatingMicButton: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pressed = false }
                nav.presentVoiceNavigator()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.appCard, Color.appCard.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.18), radius: pressed ? 3 : 10, y: pressed ? 1 : 4)
                    .overlay(
                        Circle().stroke(Color.appBorder.opacity(0.8), lineWidth: 0.5)
                    )
                PepperMarkView(size: 16, color: Color(hex: "9f1239"))
            }
            .scaleEffect(pressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice navigator")
        .accessibilityHint("Tap and speak to navigate the app, e.g. open BPC-157")
    }
}
