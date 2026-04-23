import SwiftUI

/// Universal voice import. The user can talk about either:
///   1. **What they have** — "I run BPC 250 mcg daily, Tirz 5 mg weekly"
///   2. **What they want** — "I want to recover from a knee injury and lose
///      some fat"
/// …or a mix of both. We parse the transcript through `StackParser` (for
/// compounds) and `GoalDetector` (for goals) in real time and route to the
/// right preview state automatically.
///
/// Intent priority:
///   - If we detected any compounds → "Inventory mode" → flow into preview
///     as parsed detections.
///   - Otherwise if we detected goals → "Plan mode" → flow into preview as
///     `StackRecommender` output, with rationale.
///   - Otherwise → wait. The CTA stays disabled until we have something.
///
/// One screen, two paths, fully transparent — the live "Detected" card shows
/// the user which mode they're in before they commit.
struct VoiceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceRecognitionService()

    @State private var compoundDetections: [StackParser.Detection] = []
    @State private var goalIDs: Set<String> = []
    @State private var showPreview = false
    @State private var ringPulse = false

    private enum Mode { case empty, inventory, plan }

    private var mode: Mode {
        if !compoundDetections.isEmpty { return .inventory }
        if !goalIDs.isEmpty { return .plan }
        return .empty
    }

    /// Detections that get sent to the shared preview sheet — either the
    /// parsed user-spoken stack, or the recommender's output for the
    /// detected goals.
    private var detectionsForPreview: [StackParser.Detection] {
        switch mode {
        case .inventory: return compoundDetections
        case .plan:      return StackRecommender.recommend(goals: goalIDs)
        case .empty:     return []
        }
    }

    private var previewSourceTitle: String {
        switch mode {
        case .inventory: return "From your voice"
        case .plan:      return "Recommended for you"
        case .empty:     return ""
        }
    }

    private var previewRationale: String? {
        guard mode == .plan else { return nil }
        return StackRecommender.rationaleHeader(
            goals: goalIDs,
            experience: .some,
            complexity: .balanced,
            pickedCount: detectionsForPreview.count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    explainer

                    micCard

                    if !voice.transcript.isEmpty {
                        transcriptCard
                    }

                    detectionsCard
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Voice import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { showPreview = true }
                        .bold()
                        .disabled(detectionsForPreview.isEmpty)
                }
            }
            .sheet(isPresented: $showPreview, onDismiss: { dismiss() }) {
                StackPreviewSheet(
                    initialDetections: detectionsForPreview,
                    sourceTitle: previewSourceTitle,
                    rationale: previewRationale
                )
            }
            .onChange(of: voice.transcript) { _, t in
                compoundDetections = StackParser.parse(t)
                goalIDs = GoalDetector.detect(in: t)
            }
            .onAppear { ringPulse = true }
            .onDisappear { voice.stop() }
        }
    }

    // MARK: - Sections

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell us what you have **or** what you want.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary)
            Text("Read your labels, or describe your goals — we'll figure out the rest.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)
        }
    }

    private var micCard: some View {
        VStack(spacing: 14) {
            micButton

            VStack(spacing: 4) {
                Text(headline)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appTextPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
                if let err = voice.state.errorMessage {
                    Text(err)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            VStack(spacing: 8) {
                examplePill(
                    icon: "drop.fill",
                    text: "\u{201C}BPC 250 mcg daily, Tirzepatide 5 mg weekly\u{201D}",
                    tint: Color(hex: "c2410c")
                )
                examplePill(
                    icon: "sparkles",
                    text: "\u{201C}I want to recover faster and lose some fat.\u{201D}",
                    tint: Color(hex: "166534")
                )
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
    }

    private func examplePill(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.appTextSecondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private var micButton: some View {
        Button {
            if voice.isListening {
                voice.stop()
            } else {
                if voice.state.errorMessage != nil { voice.clearError() }
                Task { await voice.start(contextualStrings: voiceVocabulary()) }
            }
        } label: {
            ZStack {
                if voice.isListening {
                    Circle()
                        .stroke(Color.appAccent.opacity(0.4), lineWidth: 2)
                        .frame(width: ringPulse ? 130 : 96, height: ringPulse ? 130 : 96)
                        .opacity(ringPulse ? 0 : 0.85)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: ringPulse)
                }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.appAccent, Color.appAccent.opacity(0.75)],
                            center: .center,
                            startRadius: 0, endRadius: 60
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(voice.isListening ? 1 + CGFloat(voice.audioLevel) * 0.18 : 1)
                    .animation(.easeOut(duration: 0.12), value: voice.audioLevel)
                    .shadow(color: Color.appAccent.opacity(0.45), radius: 14, y: 6)
                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.1)
                .foregroundColor(Color.appTextMeta)
            Text(voice.transcript)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Color.appTextPrimary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.appCardElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder.opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private var detectionsCard: some View {
        switch mode {
        case .empty:
            EmptyView()
        case .inventory:
            inventoryDetectionsCard
        case .plan:
            planDetectionsCard
        }
    }

    private var inventoryDetectionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                icon: "drop.fill",
                title: "INVENTORY DETECTED",
                subtitle: "\(compoundDetections.count) compound\(compoundDetections.count == 1 ? "" : "s")",
                tint: Color(hex: "c2410c")
            )
            ForEach(compoundDetections) { d in
                HStack {
                    Text(d.compoundName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let dose = d.doseMcg {
                        Text("\(Int(dose)) mcg")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("no dose")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "92400e"))
                    }
                    if let freq = d.frequency {
                        Text("· \(prettyFreq(freq))")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }

    private var planDetectionsCard: some View {
        let goals = GoalCategoryCatalog.sorted(Array(goalIDs))
        let recs = StackRecommender.recommend(goals: goalIDs)
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                icon: "sparkles",
                title: "GOALS DETECTED",
                subtitle: "We'll design a stack",
                tint: Color(hex: "166534")
            )
            FlowChips(goals: goals)

            Divider().overlay(Color.appBorder.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested stack")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.1)
                    .foregroundColor(Color.appTextMeta)
                ForEach(recs) { r in
                    HStack {
                        Text(r.compoundName)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if let d = r.doseMcg {
                            Text("\(Int(d)) mcg")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        if let f = r.frequency {
                            Text("· \(prettyFreq(f))")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(Color.appTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }

    private func cardHeader(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .kerning(1.1)
                .foregroundColor(Color.appTextMeta)
            Spacer()
            Text(subtitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color.appTextTertiary)
        }
    }

    private var headline: String {
        if voice.isListening { return "Listening…" }
        if voice.state.errorMessage != nil { return "Voice didn't start" }
        return "Tap to speak"
    }

    private var subtitle: String {
        if voice.isListening { return "Tap stop when you're done." }
        return "Compounds you have, goals you want — both work."
    }

    private func prettyFreq(_ token: String) -> String {
        switch token {
        case "daily":     return "daily"
        case "eod":       return "EOD"
        case "3x_weekly": return "3x/wk"
        case "2x_weekly": return "2x/wk"
        case "weekly":    return "weekly"
        case "5on_2off":  return "5on/2off"
        case "mwf":       return "MWF"
        default:          return token
        }
    }

    /// Compound vocab + goal-trigger words for better speech recognition
    /// when the user is talking about goals, not labels.
    private func voiceVocabulary() -> [String] {
        var v = CompoundCatalog.speechVocabulary
        v.append(contentsOf: [
            "recovery", "healing", "fat loss", "muscle", "growth",
            "longevity", "anti-aging", "focus", "memory", "libido",
            "skin", "hair", "immune", "sleep", "tendons", "joints"
        ])
        return v
    }
}

/// Tiny chip row for surfacing detected goal categories.
private struct FlowChips: View {
    let goals: [GoalCategory]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(goals) { g in
                HStack(spacing: 4) {
                    Image(systemName: g.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(g.display)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "166534"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: "166534").opacity(0.10)))
            }
        }
    }
}
