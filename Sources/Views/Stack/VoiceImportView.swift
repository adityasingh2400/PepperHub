import SwiftUI

/// Voice import path. Tap the mic, list off your inventory naturally, the
/// transcript flows through `StackParser` in real time, and a live preview
/// shows what we detected.
///
/// Mental model: the user holds their vials, opens this screen, taps the
/// mic, and just reads the labels. We pick out compound names, doses, and
/// frequencies as they speak.
struct VoiceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceRecognitionService()

    @State private var detections: [StackParser.Detection] = []
    @State private var showPreview = false
    @State private var ringPulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    explainer

                    micCard

                    if !voice.transcript.isEmpty {
                        transcriptCard
                    }

                    if !detections.isEmpty {
                        previewCard
                    }
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
                        .disabled(detections.isEmpty)
                }
            }
            .sheet(isPresented: $showPreview, onDismiss: { dismiss() }) {
                StackPreviewSheet(
                    initialDetections: detections,
                    sourceTitle: "From your voice"
                )
            }
            .onChange(of: voice.transcript) { _, t in
                detections = StackParser.parse(t)
            }
            .onAppear {
                ringPulse = true
            }
            .onDisappear { voice.stop() }
        }
    }

    // MARK: - Cards

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tap the mic and read out everything you have on hand.")
                .font(.system(size: 14))
                .foregroundColor(Color.appTextSecondary)
            Text("We'll pick out the compound names, doses, and frequency in real time.")
                .font(.system(size: 12))
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

            Text("Try: \u{201C}I have BPC 250 mcg daily, Tirzepatide 5 mg weekly, Ipamorelin 200 mcg every other day.\u{201D}")
                .font(.system(size: 11))
                .foregroundColor(Color.appTextMeta)
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
    }

    private var micButton: some View {
        Button {
            if voice.isListening {
                voice.stop()
            } else {
                if voice.state.errorMessage != nil { voice.clearError() }
                Task { await voice.start(contextualStrings: CompoundCatalog.speechVocabulary) }
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

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.appAccent)
                    .font(.system(size: 12, weight: .bold))
                Text("DETECTED")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.1)
                    .foregroundColor(Color.appTextMeta)
                Spacer()
                Text("\(detections.count) compound\(detections.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.appTextTertiary)
            }
            ForEach(detections) { d in
                HStack {
                    Text(d.compoundName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let dose = d.doseMcg {
                        Text("\(Int(dose)) mcg").font(.system(size: 12, weight: .semibold, design: .rounded))
                    } else {
                        Text("no dose").font(.system(size: 11)).foregroundColor(Color(hex: "92400e"))
                    }
                    if let freq = d.frequency {
                        Text("· \(freq.replacingOccurrences(of: "_", with: " "))")
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

    private var headline: String {
        if voice.isListening { return "Listening…" }
        if voice.state.errorMessage != nil { return "Voice didn't start" }
        return "Tap to speak"
    }

    private var subtitle: String {
        if voice.isListening {
            return "Tap stop when you're done."
        }
        return "We'll show what we detect as you talk."
    }
}
