import SwiftUI

/// Voice-first multi-select for peptide compounds. Tap the mic and speak names
/// (or aliases like "Ozempic"); compounds auto-add as they're recognized.
/// Type or tap chips for everyone else.
struct CompoundPickerView: View {
    @Binding var selected: Set<String>
    @StateObject private var voice = VoiceRecognitionService()
    @State private var search: String = ""
    @State private var showAll: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                voiceCard

                if !selected.isEmpty {
                    selectedSection
                }

                searchField

                chipGrid

                if !showAll && search.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAll = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Show all \(CompoundCatalog.all.count)")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.appAccent)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onChange(of: voice.transcript) { _, newValue in
            applyVoiceMatches(from: newValue)
        }
    }

    // MARK: - Voice card

    private var voiceCard: some View {
        Button {
            if voice.state.errorMessage != nil { voice.clearError() }
            Task { await voice.start(contextualStrings: CompoundCatalog.speechVocabulary) }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    micButton
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headlineForVoice)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(voiceHasError ? Color(hex: "b91c1c") : Color.appTextPrimary)
                        Text(subtitleForVoice)
                            .font(.system(size: 13))
                            .foregroundColor(voiceHasError ? Color(hex: "b91c1c").opacity(0.8) : Color.appTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if voice.isListening {
                    waveform
                }

                if !voice.transcript.isEmpty {
                    Text(voice.transcript)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.appTextSecondary)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .background(Color.appCard)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(voiceCardStrokeColor,
                            lineWidth: (voice.isListening || voiceHasError) ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var voiceHasError: Bool { voice.state.errorMessage != nil }

    private var voiceCardStrokeColor: Color {
        if voiceHasError { return Color(hex: "b91c1c") }
        if voice.isListening { return Color.appAccent }
        return Color.appBorder
    }

    private var micButton: some View {
        ZStack {
            Circle()
                .fill(Color.appAccent)
                .frame(width: 48, height: 48)
                .scaleEffect(voice.isListening ? 1 + CGFloat(voice.audioLevel) * 0.25 : 1)
                .animation(.easeOut(duration: 0.12), value: voice.audioLevel)
            Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: 3, height: barHeight(at: i))
                    .animation(.easeOut(duration: 0.15), value: voice.audioLevel)
            }
            Spacer()
        }
        .frame(height: 22)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let phase: [CGFloat] = [0.4, 0.8, 1.0, 0.7, 0.5]
        let base: CGFloat = 6
        let max: CGFloat = 22
        let lvl = CGFloat(voice.audioLevel)
        return base + (max - base) * phase[index] * (0.4 + lvl * 0.6)
    }

    private var headlineForVoice: String {
        switch voice.state {
        case .listening:            return "Listening…"
        case .requestingPermission: return "Asking permission…"
        case .denied:               return "Voice blocked"
        case .unsupported:          return "Voice unavailable"
        case .error:                return "Voice didn't start"
        case .idle:                 return "Tap to speak"
        }
    }

    private var subtitleForVoice: String {
        if voice.isListening {
            return voice.transcript.isEmpty ? "Say a peptide name. Tap again when done." : " "
        }
        if let msg = voice.state.errorMessage { return msg }
        return "Try “BPC-157, Tirzepatide, Ipamorelin.”"
    }

    private func applyVoiceMatches(from text: String) {
        let matches = CompoundCatalog.match(in: text)
        guard !matches.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            for m in matches { _ = selected.insert(m) }
        }
    }

    // MARK: - Selected chips

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECTED (\(selected.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(selected).sorted(), id: \.self) { name in
                    SelectedChip(label: name) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            _ = selected.remove(name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextTertiary)
            TextField("Search compounds…", text: $search)
                .font(.system(size: 15))
                .foregroundColor(Color.appTextPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.appTextTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder, lineWidth: 1.5)
        )
        .onChange(of: search) { _, _ in
            if !search.isEmpty { showAll = true }
        }
    }

    // MARK: - Chip grid

    private var chipGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chipSectionTitle)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(displayedCompounds, id: \.self) { name in
                    CompoundChip(label: name, selected: selected.contains(name)) {
                        toggle(name)
                    }
                }
            }
            if displayedCompounds.isEmpty {
                Text("No matches. Try a different name.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextTertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var chipSectionTitle: String {
        if !search.isEmpty { return "RESULTS" }
        return showAll ? "ALL COMPOUNDS" : "POPULAR"
    }

    private var displayedCompounds: [String] {
        let pool: [String] = showAll || !search.isEmpty
            ? CompoundCatalog.all.map(\.canonical)
            : CompoundCatalog.popular
        guard !search.isEmpty else { return pool }
        let needle = CompoundCatalog.normalize(search)
        return pool.filter { name in
            // Match canonical name or any alias
            if CompoundCatalog.normalize(name).contains(needle) { return true }
            if let entry = CompoundCatalog.all.first(where: { $0.canonical == name }) {
                return entry.aliases.contains { CompoundCatalog.normalize($0).contains(needle) }
            }
            return false
        }
    }

    private func toggle(_ name: String) {
        let wasSearching = !search.isEmpty
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if selected.contains(name) {
                _ = selected.remove(name)
            } else {
                _ = selected.insert(name)
            }
            // Clear the search field after picking a result so the next
            // compound can be typed immediately.
            if wasSearching { search = "" }
        }
    }
}

// MARK: - Chip subviews

private struct CompoundChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: selected ? .bold : .semibold))
                .foregroundColor(selected ? .white : Color.appTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? Color.appAccent : Color.appCard)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SelectedChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Color.appAccent)
        .cornerRadius(20)
        .transition(.scale.combined(with: .opacity))
    }
}
