import SwiftUI

struct ResearchListView: View {
    var body: some View {
        NavigationStack {
            EmbeddedResearchView()
                .navigationTitle("Research")
        }
    }
}

struct EmbeddedResearchView: View {
    @State private var compounds: [Compound] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var filtered: [Compound] {
        if searchText.isEmpty { return compounds }
        return compounds.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.benefits.joined().localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Text("Couldn't load compounds")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextTertiary)
                    Button("Retry") { Task { await load() } }
                        .foregroundColor(Color.appAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("Try a different compound name or benefit.")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { compound in
                            NavigationLink(destination: CompoundDetailView(compound: compound).onAppear {
                                Analytics.capture(.compoundViewed, properties: ["compound": compound.name])
                            }) {
                                CompoundRowView(compound: compound)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(Color.appBackground)
            }
        }
        .navigationTitle("Research")
        .searchable(text: $searchText, prompt: "Search compounds")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result: [Compound] = try await Task.detached {
                try await supabase
                    .from("compounds")
                    .select()
                    .order("name")
                    .execute()
                    .value
            }.value
            compounds = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct CompoundRowView: View {
    let compound: Compound

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(compound.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    FDABadge(status: compound.fdaStatus)
                }
                Text(compound.benefits.prefix(2).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.appTextMeta)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}

struct CompoundDetailView: View {
    let compound: Compound

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(compound.name)
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(Color.appTextPrimary)
                        Spacer()
                        FDABadge(status: compound.fdaStatus)
                    }
                    if let halfLife = compound.halfLifeHrs {
                        Label("Half-life: \(halfLife < 24 ? "\(Int(halfLife))h" : "\(Int(halfLife/24))d")",
                              systemImage: "clock")
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextTertiary)
                    }
                    if let low = compound.dosingRangeLowMcg, let high = compound.dosingRangeHighMcg {
                        Label("Dosing: \(Int(low))–\(Int(high)) mcg", systemImage: "syringe")
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
                .padding(16)
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))

                // Summary
                if let summary = compound.summaryMd {
                    InfoSection(title: "Overview") {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundColor(Color.appTextSecondary)
                            .lineSpacing(4)
                    }
                }

                // Benefits
                InfoSection(title: "Benefits") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(compound.benefits, id: \.self) { benefit in
                            Label(benefit, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }
                }

                // Side effects
                InfoSection(title: "Side Effects") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(compound.sideEffects, id: \.self) { effect in
                            Label(effect, systemImage: "info.circle")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }
                }

                // Stacking notes
                if let notes = compound.stackingNotes {
                    InfoSection(title: "Stacking Notes") {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextSecondary)
                    }
                }

                Text("For educational and research purposes only. Not medical advice.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle(compound.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)
            content
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct FDABadge: View {
    let status: Compound.FDAStatus

    var label: String {
        switch status {
        case .approved: return "FDA Approved"
        case .grey:     return "Grey Market"
        case .research: return "Research"
        }
    }

    var color: Color {
        switch status {
        case .approved: return Color(hex: "166534")
        case .grey:     return Color(hex: "92400e")
        case .research: return Color(hex: "1e40af")
        }
    }

    var bg: Color {
        switch status {
        case .approved: return Color(hex: "dcfce7")
        case .grey:     return Color(hex: "fef3c7")
        case .research: return Color(hex: "dbeafe")
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .cornerRadius(20)
    }
}
