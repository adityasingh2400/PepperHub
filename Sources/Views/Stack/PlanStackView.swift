import SwiftUI

/// "Plan a stack from scratch" flow.
///
/// 3 quick refinement questions on top of the user's onboarding goals:
///   1. Goals (multi-select, pre-filled from onboarding if available)
///   2. Experience level (new / some / veteran)
///   3. Stack complexity (simple / balanced / advanced)
///
/// Each step swaps in place — like Step 1 / 2 / 3 of a one-screen wizard, no
/// navigation churn. We carry just three pieces of state, then call
/// `recommend(...)` to score the catalog deterministically against goals +
/// experience + complexity. Zero LLM cost.
struct PlanStackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .goals
    @State private var goals: Set<String>
    @State private var experience: Experience = .some
    @State private var complexity: Complexity = .balanced
    @State private var showPreview = false

    enum Step: Int, CaseIterable {
        case goals = 0, experience = 1, complexity = 2
    }

    enum Experience: String, CaseIterable, Identifiable {
        case new      = "New to peptides"
        case some     = "Some experience"
        case veteran  = "Veteran"
        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .new:     return "I want a gentle first stack."
            case .some:    return "I've run a cycle or two."
            case .veteran: return "Stack me high — I know what I'm doing."
            }
        }
    }

    enum Complexity: String, CaseIterable, Identifiable {
        case simple   = "Simple"
        case balanced = "Balanced"
        case advanced = "Advanced"
        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .simple:   return "1–2 compounds. Easy to manage."
            case .balanced: return "3 compounds. Most people land here."
            case .advanced: return "4+ compounds. Synergy stacking."
            }
        }

        var maxCompounds: Int {
            switch self {
            case .simple:   return 2
            case .balanced: return 3
            case .advanced: return 5
            }
        }
    }

    init(prefilledGoals: Set<String> = []) {
        _goals = State(initialValue: prefilledGoals)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case .goals:      goalsStep
                        case .experience: experienceStep
                        case .complexity: complexityStep
                        }
                    }
                    .padding(20)
                }

                actionBar
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Plan a stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreview, onDismiss: { dismiss() }) {
                StackPreviewSheet(
                    initialDetections: recommend(),
                    sourceTitle: "Recommended for you",
                    rationale: rationale()
                )
            }
        }
    }

    // MARK: - Progress + actions

    private var progressBar: some View {
        let totalSteps = Step.allCases.count
        let progress = Double(step.rawValue + 1) / Double(totalSteps)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appBorder).frame(height: 3)
                Capsule().fill(Color.appAccent)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if step.rawValue > 0 {
                Button {
                    if let prev = Step(rawValue: step.rawValue - 1) {
                        withAnimation { step = prev }
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary)
                        .frame(width: 88, height: 48)
                        .background(Color.appCard)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                if let next = Step(rawValue: step.rawValue + 1) {
                    withAnimation { step = next }
                } else {
                    showPreview = true
                }
            } label: {
                Text(step == .complexity ? "Generate stack" : "Continue")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.appAccent)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(step == .goals && goals.isEmpty)
        }
        .padding(16)
        .background(Color.appBackground)
    }

    // MARK: - Steps

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you want from peptides?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
            Text("Pick all that apply. We'll pick compounds that hit these targets.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)

            let columns = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GoalCategoryCatalog.all) { goal in
                    let selected = goals.contains(goal.id)
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if selected { goals.remove(goal.id) } else { goals.insert(goal.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: goal.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(selected ? .white : Color.appAccent)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle().fill(selected ? Color.white.opacity(0.18) : Color.appAccentTint)
                                )
                            Text(goal.display)
                                .font(.system(size: 13, weight: .bold))
                                .multilineTextAlignment(.leading)
                                .foregroundColor(selected ? .white : Color.appTextPrimary)
                            Text(goal.description)
                                .font(.system(size: 10))
                                .foregroundColor(selected ? Color.white.opacity(0.85) : Color.appTextTertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(selected ? Color.appAccent : Color.appCard)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How experienced are you with peptides?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
            Text("We tune dose ranges and stack risk for your level.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)
            VStack(spacing: 10) {
                ForEach(Experience.allCases) { e in
                    bigChoice(
                        title: e.rawValue,
                        subtitle: e.subtitle,
                        isSelected: experience == e
                    ) {
                        experience = e
                    }
                }
            }
        }
    }

    private var complexityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How big should we go?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
            Text("More compounds = more synergy, more management.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)
            VStack(spacing: 10) {
                ForEach(Complexity.allCases) { c in
                    bigChoice(
                        title: c.rawValue,
                        subtitle: c.subtitle,
                        isSelected: complexity == c
                    ) {
                        complexity = c
                    }
                }
            }
        }
    }

    private func bigChoice(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.appAccent : Color.appBorder, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.appAccent).frame(width: 12, height: 12)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
            }
            .padding(14)
            .background(isSelected ? Color.appAccentTint : Color.appCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.appAccent : Color.appBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recommendation engine

    /// Score every catalog compound against the user's goals + experience and
    /// return the top N as detections (so they flow through the same preview
    /// screen as the import paths).
    func recommend() -> [StackParser.Detection] {
        // 1. Score by goal overlap.
        var scored: [(Compound, Int)] = CompoundCatalog.allCompoundsSeed.compactMap { c in
            let overlap = c.goalCategories.filter(goals.contains).count
            guard overlap > 0 else { return nil }
            return (c, overlap)
        }

        // 2. Tilt toward FDA-approved compounds for new users; let veterans
        //    see research-status compounds too.
        if experience == .new {
            scored = scored.map { (c, score) in
                let bonus = (c.fdaStatus == .approved) ? 2 : 0
                return (c, score + bonus)
            }
        }

        // 3. Sort: highest score first, ties broken by name for determinism.
        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name < $1.0.name
        }

        // 4. Cap by complexity preference.
        let cap = complexity.maxCompounds
        let picked = scored.prefix(cap)

        // 5. Convert to detections with sensible defaults.
        return picked.map { (c, _) in
            let dose: Double = {
                guard let low = c.dosingRangeLowMcg, let high = c.dosingRangeHighMcg else { return 100 }
                // New users start near the low end of the published range; veterans mid.
                let mix: Double = experience == .new ? 0.25 : 0.5
                return ((low * (1 - mix)) + (high * mix)).rounded()
            }()
            return StackParser.Detection(
                compoundName: c.name,
                doseMcg: dose,
                frequency: c.dosingFrequency ?? "daily",
                sourceSegment: rationaleFor(c),
                confidence: 1.0
            )
        }
    }

    private func rationaleFor(_ c: Compound) -> String {
        let matched = c.goalCategories.filter(goals.contains)
            .compactMap { GoalCategoryCatalog.find($0)?.display.lowercased() }
        if matched.isEmpty { return "" }
        return "Picked for " + matched.joined(separator: ", ")
    }

    private func rationale() -> String {
        let goalNames = GoalCategoryCatalog.sorted(Array(goals))
            .map(\.display)
            .joined(separator: ", ")
        let count = recommend().count
        return "We picked \(count) compound\(count == 1 ? "" : "s") for **\(goalNames)** at a \(complexity.rawValue.lowercased()) starting dose for a \(experience.rawValue.lowercased()) user. Tweak anything below."
    }
}
