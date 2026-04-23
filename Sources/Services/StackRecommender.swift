import Foundation

/// Deterministic stack recommendation engine.
///
/// Given a set of goal IDs (from `GoalDetector` or the onboarding goal grid)
/// and an experience tilt, returns a curated list of compounds shaped as
/// `StackParser.Detection` so the result can flow through the same preview
/// screen as the import paths.
///
/// Why no LLM:
///   The recommendation surface is the 24-compound seed catalog. Scoring by
///   goal-overlap + experience tilt gives a stable, defensible answer in
///   microseconds, with zero API cost. We can layer LLM-driven explanations
///   on top later without changing the core decision.
enum StackRecommender {

    enum Experience {
        case new, some, veteran
    }

    enum Complexity {
        case simple, balanced, advanced

        var maxCompounds: Int {
            switch self {
            case .simple:   return 2
            case .balanced: return 3
            case .advanced: return 5
            }
        }
    }

    /// Returns up to `complexity.maxCompounds` detections, ordered most→least
    /// relevant. Each detection has a sensible default dose (low end of the
    /// published range for new users, midpoint for everyone else) and the
    /// compound's recommended frequency.
    static func recommend(
        goals: Set<String>,
        experience: Experience = .some,
        complexity: Complexity = .balanced
    ) -> [StackParser.Detection] {
        guard !goals.isEmpty else { return [] }

        // 1. Score by goal overlap.
        var scored: [(Compound, Int)] = CompoundCatalog.allCompoundsSeed.compactMap { c in
            let overlap = c.goalCategories.filter(goals.contains).count
            guard overlap > 0 else { return nil }
            return (c, overlap)
        }

        // 2. Tilt toward FDA-approved compounds for new users.
        if experience == .new {
            scored = scored.map { (c, score) in
                let bonus = (c.fdaStatus == .approved) ? 2 : 0
                return (c, score + bonus)
            }
        }

        // 3. Stable sort.
        scored.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name < $1.0.name
        }

        let picked = scored.prefix(complexity.maxCompounds)

        // 4. Convert to detections.
        return picked.map { (c, _) in
            StackParser.Detection(
                compoundName: c.name,
                doseMcg: defaultDose(for: c, experience: experience),
                frequency: c.dosingFrequency ?? "daily",
                sourceSegment: rationale(for: c, goals: goals),
                confidence: 1.0
            )
        }
    }

    // MARK: - Helpers

    private static func defaultDose(for c: Compound, experience: Experience) -> Double? {
        guard let low = c.dosingRangeLowMcg, let high = c.dosingRangeHighMcg else {
            return nil
        }
        // New users start near the low end; everyone else lands at midpoint.
        let mix: Double = experience == .new ? 0.25 : 0.5
        return ((low * (1 - mix)) + (high * mix)).rounded()
    }

    private static func rationale(for c: Compound, goals: Set<String>) -> String {
        let matched = c.goalCategories
            .filter(goals.contains)
            .compactMap { GoalCategoryCatalog.find($0)?.display.lowercased() }
        guard !matched.isEmpty else { return "" }
        return "Picked for " + matched.joined(separator: ", ")
    }

    /// Human-readable rationale string for the preview header. Same shape
    /// PlanStackView used; kept here so the voice flow gets it for free.
    static func rationaleHeader(
        goals: Set<String>,
        experience: Experience,
        complexity: Complexity,
        pickedCount: Int
    ) -> String {
        let goalNames = GoalCategoryCatalog.sorted(Array(goals))
            .map(\.display)
            .joined(separator: ", ")
        let expWord: String = {
            switch experience {
            case .new:     return "new"
            case .some:    return "intermediate"
            case .veteran: return "advanced"
            }
        }()
        let complexityWord: String = {
            switch complexity {
            case .simple:   return "simple"
            case .balanced: return "balanced"
            case .advanced: return "advanced"
            }
        }()
        return "We picked \(pickedCount) compound\(pickedCount == 1 ? "" : "s") for **\(goalNames)** at a \(complexityWord) starting dose for a \(expWord) user. Tweak anything below."
    }
}
