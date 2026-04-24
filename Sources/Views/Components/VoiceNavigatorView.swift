import SwiftUI
import SwiftData

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

    enum Phase { case listening, thinking, speaking }

    var body: some View {
        GeometryReader { proxy in
            let voiceCenter = voiceButtonCenter(in: proxy.size)
            let topInset = inferredTopSafeInset(proxy)
            ZStack(alignment: .bottomTrailing) {
                VoicePerimeterGlow(
                    progress: traceProgress,
                    isSettled: glowSettled,
                    showRipple: completionRipple,
                    audioLevel: CGFloat(voice.audioLevel),
                    sourcePoint: voiceCenter,
                    sourceYRatio: voiceCenter.y / max(proxy.size.height, 1),
                    topSafeInset: topInset
                )
                .allowsHitTesting(false)

                if let text = captionText {
                    VoiceCaptionPill(text: text)
                        .padding(.trailing, 18)
                        .padding(.bottom, 212)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                VStack(spacing: 10) {
                    voiceControlButton
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 96)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
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
            tts.stop()
        }
        .onChange(of: voice.transcript) { _, newValue in
            scheduleAutoSubmit(for: newValue)
        }
        .onChange(of: pepperService.messages.count) { _, _ in
            speakLatestAssistantIfNeeded()
        }
        .onChange(of: pepperService.messages.last?.text ?? "") { _, _ in
            speakLatestAssistantIfNeeded()
        }
        .onChange(of: pepperService.isStreaming) { _, _ in
            speakLatestAssistantIfNeeded()
        }
        .onChange(of: pepperService.pendingToolCall?.id) { _, newValue in
            if newValue != nil {
                nav.presentPepper()
                closeAfterCompletion(delay: 0.2)
            }
        }
        .onChange(of: tts.playingId) { old, new in
            if old != nil && new == nil && phase == .speaking {
                closeAfterCompletion(delay: 0.35)
            }
        }
        .onChange(of: tts.lastError ?? "") { _, newValue in
            if !newValue.isEmpty && phase == .speaking {
                closeAfterCompletion(delay: 0.6)
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
            ZStack {
                if phase == .listening {
                    Circle()
                        .fill(Color.appAccent.opacity(0.24))
                        .frame(width: 72, height: 72)
                        .scaleEffect(1 + CGFloat(voice.audioLevel) * 0.35)
                        .opacity(0.85)
                        .animation(.easeOut(duration: 0.16), value: voice.audioLevel)
                }

                Circle()
                    .fill(Color(hex: "9f1239"))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(hex: "9f1239").opacity(0.8), radius: phase == .thinking ? 24 : 16, y: 6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(glowSettled ? 0.34 : 0.14), lineWidth: 1)
                    )
                    .scaleEffect(phase == .thinking ? 1.04 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: phase == .thinking)

                Image(systemName: controlIconName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, options: .repeating, value: phase == .thinking)
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Voice assistant")
        .accessibilityHint(phase == .listening ? "Tap to submit." : "Tap to cancel.")
    }

    private var controlIconName: String {
        switch phase {
        case .listening: return voice.transcript.isEmpty ? "mic.fill" : "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var captionText: String? {
        if let err = voice.state.errorMessage { return err }
        let transcript = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        switch phase {
        case .listening:
            return transcript.isEmpty ? nil : "\"\(transcript)\""
        case .thinking:
            return "Navigating..."
        case .speaking:
            return "Done"
        }
    }

    private func voiceButtonCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - 44, y: size.height - 174)
    }

    private func inferredTopSafeInset(_ proxy: GeometryProxy) -> CGFloat {
        if proxy.safeAreaInsets.top > 0 {
            return proxy.safeAreaInsets.top
        }
        return proxy.size.height >= 780 ? 47 : 0
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

    private func scheduleAutoSubmit(for transcript: String) {
        guard phase == .listening else { return }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        autoSubmitTask?.cancel()
        guard trimmed.count > 1 else { return }

        autoSubmitTask = Task {
            try? await Task.sleep(nanoseconds: 1_150_000_000)
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
        guard phase == .listening else { return }
        autoSubmitTask?.cancel()
        let trimmed = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.stop()

        guard !trimmed.isEmpty else {
            closeNow()
            return
        }
        guard let userId = authManager.session?.user.id.uuidString else {
            closeNow()
            return
        }

        phase = .thinking
        sentMessageStartIndex = pepperService.messages.count
        Task {
            await pepperService.send(userMessage: trimmed, modelContext: modelContext, userId: userId)
            await MainActor.run { speakLatestAssistantIfNeeded() }
        }
    }

    private func speakLatestAssistantIfNeeded() {
        if pepperService.pendingToolCall != nil {
            nav.presentPepper()
            closeAfterCompletion(delay: 0.2)
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
        phase = .speaking
        ttsId = UUID()
        tts.toggle(pepperService.messages[lastIdx].text, id: ttsId)

        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if phase == .speaking && tts.loadingId == nil && tts.playingId == nil {
                    closeAfterCompletion(delay: 0.2)
                }
            }
        }
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
        withAnimation(.easeInOut(duration: 0.22)) {
            nav.dismissVoiceNavigator()
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
    let topSafeInset: CGFloat
    var flowEnabled = true

    @State private var flowPhase = false

    var body: some View {
        ZStack {
            perimeter(progress)
                .stroke(Color(hex: "9f1239").opacity(0.52), style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round))
                .blur(radius: 20 + audioLevel * 14)
                .opacity(isSettled ? 0.95 : 0.8)

            perimeter(progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "6f001f"),
                            Color(hex: "b50f46"),
                            Color(hex: "fff0cf"),
                            Color(hex: "8f0a35"),
                            Color(hex: "f7d99c"),
                            Color(hex: "6f001f")
                        ],
                        center: .center,
                        angle: .degrees(flowPhase ? 360 : 0)
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Color(hex: "9f1239").opacity(0.86), radius: isSettled ? 22 + audioLevel * 16 : 10)

            if isSettled {
                perimeter(1)
                    .stroke(
                        AngularGradient(
                            colors: [
                                .clear,
                                Color(hex: "fff7dc").opacity(0.95),
                                .clear,
                                Color(hex: "f0b8bf").opacity(0.65),
                                .clear
                            ],
                            center: .center,
                            angle: .degrees(flowPhase ? 560 : 200)
                        ),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 1.6)
                    .blendMode(.screen)
                    .mask(
                        perimeter(1)
                            .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                    )

                perimeter(1)
                    .stroke(Color(hex: "4f0018").opacity(0.72), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                perimeter(1)
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .blendMode(.screen)
            }

            if showRipple {
                Circle()
                    .stroke(Color(hex: "9f1239").opacity(0.75), lineWidth: 2.5)
                    .frame(width: 76, height: 76)
                    .position(sourcePoint)
                    .transition(.scale(scale: 0.15).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: audioLevel)
        .animation(.easeOut(duration: 0.42), value: showRipple)
        .drawingGroup()
        .onAppear {
            guard flowEnabled else {
                flowPhase = true
                return
            }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                flowPhase = true
            }
        }
    }

    private func perimeter(_ progress: CGFloat) -> VoicePerimeterShape {
        VoicePerimeterShape(progress: progress, sourceYRatio: sourceYRatio, topSafeInset: topSafeInset)
    }
}

private struct VoicePerimeterShape: Shape {
    var progress: CGFloat
    var sourceYRatio: CGFloat
    var topSafeInset: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, sourceYRatio) }
        set {
            progress = newValue.first
            sourceYRatio = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 0.8
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let radius = min(bounds.width, bounds.height) * 0.055
        let r = min(max(radius, 22), 36)
        let sourceY = min(
            max(bounds.minY + bounds.height * sourceYRatio, bounds.minY + r),
            bounds.maxY - r
        )
        let notch = notchMetrics(in: bounds)

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
        if let notch {
            path.addLine(to: CGPoint(x: notch.left - notch.shoulder, y: bounds.minY))
            path.addCurve(
                to: CGPoint(x: notch.left, y: bounds.minY + notch.depth * 0.54),
                control1: CGPoint(x: notch.left - notch.shoulder * 0.36, y: bounds.minY),
                control2: CGPoint(x: notch.left, y: bounds.minY + notch.depth * 0.16)
            )
            path.addCurve(
                to: CGPoint(x: notch.left + notch.shoulder, y: bounds.minY + notch.depth),
                control1: CGPoint(x: notch.left, y: bounds.minY + notch.depth * 0.86),
                control2: CGPoint(x: notch.left + notch.shoulder * 0.34, y: bounds.minY + notch.depth)
            )
            path.addLine(to: CGPoint(x: notch.right - notch.shoulder, y: bounds.minY + notch.depth))
            path.addCurve(
                to: CGPoint(x: notch.right, y: bounds.minY + notch.depth * 0.54),
                control1: CGPoint(x: notch.right - notch.shoulder * 0.34, y: bounds.minY + notch.depth),
                control2: CGPoint(x: notch.right, y: bounds.minY + notch.depth * 0.86)
            )
            path.addCurve(
                to: CGPoint(x: notch.right + notch.shoulder, y: bounds.minY),
                control1: CGPoint(x: notch.right, y: bounds.minY + notch.depth * 0.16),
                control2: CGPoint(x: notch.right + notch.shoulder * 0.36, y: bounds.minY)
            )
        }
        path.addLine(to: CGPoint(x: bounds.maxX - r, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + r),
            control: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: sourceY))

        return path.trimmedPath(from: 0, to: min(max(progress, 0), 1))
    }

    private func notchMetrics(in bounds: CGRect) -> (left: CGFloat, right: CGFloat, depth: CGFloat, shoulder: CGFloat)? {
        guard topSafeInset >= 38, bounds.width >= 320 else { return nil }
        let centerX = bounds.midX
        let halfWidth = min(max(bounds.width * 0.205, 72), 92)
        let depth = min(max(topSafeInset - 10, 30), 42)
        let shoulder = min(max(bounds.width * 0.048, 16), 22)
        return (
            left: centerX - halfWidth,
            right: centerX + halfWidth,
            depth: depth,
            shoulder: shoulder
        )
    }
}

struct VoiceNavigatorPrewarmView: View {
    var body: some View {
        GeometryReader { proxy in
            let sourcePoint = CGPoint(x: proxy.size.width - 44, y: proxy.size.height - 174)
            let topInset = proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : (proxy.size.height >= 780 ? 47 : 0)
            VoicePerimeterGlow(
                progress: 1,
                isSettled: true,
                showRipple: false,
                audioLevel: 0,
                sourcePoint: sourcePoint,
                sourceYRatio: sourcePoint.y / max(proxy.size.height, 1),
                topSafeInset: topInset,
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
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.appAccent)
            }
            .scaleEffect(pressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice navigator")
        .accessibilityHint("Tap and speak to navigate the app, e.g. open BPC-157")
    }
}
