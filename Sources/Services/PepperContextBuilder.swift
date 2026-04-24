import Foundation
import SwiftData

@MainActor
struct PepperContextBuilder {

    static func buildSystemPrompt(userId: String, modelContext: ModelContext) -> String {
        let now = Date()
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var parts: [String] = []

        parts.append("""
        You are Pepper, the AI assistant built into the Pepper app. You have full access to this user's logged health data and can take actions in the app on their behalf.

        You have two roles: (1) interpret the user's own logged data, and (2) share educational information about peptides and protocols when asked.

        For data questions, frame responses as "based on your logs" or "your data shows."

        For peptide and protocol questions, share what is publicly known from research literature and community experience — mechanisms, timing, common dosing ranges, interactions, side effect profiles. You are an information resource, not a doctor. Any response that discusses peptide protocols, dosing, or effects must end with this disclaimer on its own line: "Note: Educational information only, not medical advice. Consult a healthcare professional before changing your protocol."

        IMPORTANT: Never use markdown formatting. No headers (###), no bold (**text**), no tables, no bullet lists with dashes or asterisks, no horizontal rules (---). Write in plain conversational prose only, like a text message. Keep responses concise.

        Today: \(formatter.string(from: now))
        Timezone: \(TimeZone.current.identifier)
        """)

        // User profile
        if let profile = fetchProfile(userId: userId, context: modelContext) {
            parts.append("""
            ## User Profile
            Weight: \(String(format: "%.1f", profile.weightKg)) kg | Height: \(String(format: "%.0f", profile.heightCm)) cm | Age: \(profile.ageYears)
            Sex: \(profile.biologicalSex) | Activity: \(profile.activityLevel) | Goal: \(profile.goal)
            Experience: \(profile.experience) | Training: \(profile.trainingDaysPerWeek)x/week | Diet style: \(profile.eatingStyle)
            TDEE: \(Int(profile.tdeeKcal)) kcal/day | Target: \(Int(profile.calorieTargetKcal)) kcal/day
            Macro targets: \(profile.macroGoalProteinG)g protein / \(profile.macroGoalCarbsG)g carbs / \(profile.macroGoalFatG)g fat
            """)
        }

        // Active protocol
        let protocols = fetchProtocols(userId: userId, context: modelContext)
        if let activeProtocol = protocols.first(where: { $0.isActive }) {
            let compounds = activeProtocol.compounds.map { c in
                "  - \(c.compoundName): \(c.doseMcg) mcg, \(c.frequency), times: \(c.doseTimes.joined(separator: ", "))"
            }.joined(separator: "\n")
            parts.append("""
            ## Active Protocol: \(activeProtocol.name)
            Started: \(formatter.string(from: activeProtocol.startDate))
            Compounds:
            \(compounds)
            """)
        }

        // Last 14 days of dose logs
        let doseCutoff = calendar.date(byAdding: .day, value: -14, to: now)!
        let doseLogs = fetchDoseLogs(userId: userId, since: doseCutoff, context: modelContext)
        if !doseLogs.isEmpty {
            let doseLines = doseLogs.prefix(60).map { d in
                "  \(formatter.string(from: d.dosedAt)): \(d.compoundName) \(d.doseMcg) mcg\(d.injectionSite.isEmpty ? "" : " @ \(d.injectionSite)")\(d.notes.isEmpty ? "" : " (\(d.notes))")"
            }.joined(separator: "\n")
            parts.append("## Dose Logs (last 14 days)\n\(doseLines)")
        }

        // Last 7 days of food logs (summarized by day)
        let foodCutoff = calendar.date(byAdding: .day, value: -7, to: now)!
        let foodLogs = fetchFoodLogs(userId: userId, since: foodCutoff, context: modelContext)
        if !foodLogs.isEmpty {
            let byDay = Dictionary(grouping: foodLogs) { log -> String in
                let df = DateFormatter()
                df.dateFormat = "EEEE MMM d"
                return df.string(from: log.loggedAt)
            }
            let dayLines = byDay.sorted { $0.key < $1.key }.map { (day, logs) -> String in
                let totalKcal = logs.reduce(0) { $0 + $1.kcal }
                let totalProtein = logs.reduce(0.0) { $0 + $1.proteinG }
                let totalCarbs = logs.reduce(0.0) { $0 + $1.carbsG }
                let totalFat = logs.reduce(0.0) { $0 + $1.fatG }
                let items = logs.prefix(20).map { "\($0.foodName) (\($0.kcal) kcal, \(Int($0.proteinG))g P)" }.joined(separator: ", ")
                return "  \(day): \(totalKcal) kcal | \(Int(totalProtein))g P / \(Int(totalCarbs))g C / \(Int(totalFat))g F\n    Foods: \(items)"
            }.joined(separator: "\n")
            parts.append("## Food Logs (last 7 days)\n\(dayLines)")
        }

        // Last 7 days of side effects
        let seCutoff = calendar.date(byAdding: .day, value: -7, to: now)!
        let sideEffects = fetchSideEffects(userId: userId, since: seCutoff, context: modelContext)
        if !sideEffects.isEmpty {
            let seLines = sideEffects.prefix(30).map { s in
                "  \(formatter.string(from: s.loggedAt)): \(s.symptom) (severity \(s.severity)/10)\(s.linkedCompoundName.map { " — linked to \($0)" } ?? "")"
            }.joined(separator: "\n")
            parts.append("## Side Effects (last 7 days)\n\(seLines)")
        }

        // Last 7 days of workouts
        let workoutCutoff = calendar.date(byAdding: .day, value: -7, to: now)!
        let workouts = fetchWorkouts(userId: userId, since: workoutCutoff, context: modelContext)
        if !workouts.isEmpty {
            let workoutLines = workouts.prefix(20).map { w in
                "  \(formatter.string(from: w.loggedAt)): \(w.type), \(w.durationMinutes) min\(w.notes.isEmpty ? "" : " — \(w.notes)")"
            }.joined(separator: "\n")
            parts.append("## Workouts (last 7 days)\n\(workoutLines)")
        }

        // Exercise logs (last 7 days)
        let exerciseLogs = fetchExerciseLogs(userId: userId, since: workoutCutoff, context: modelContext)
        if !exerciseLogs.isEmpty {
            let exLines = exerciseLogs.prefix(30).map { e in
                "  \(formatter.string(from: e.loggedAt)): \(e.exerciseName) (\(e.muscleGroup))"
            }.joined(separator: "\n")
            parts.append("## Exercise Logs (last 7 days)\n\(exLines)")
        }

        // Navigation anchors currently registered in the UI. Only spotlight IDs
        // that appear in this list — unknown IDs will silently no-op.
        let compoundSlugs: [String] = {
            guard let active = protocols.first(where: { $0.isActive }) else { return [] }
            return active.compounds.map { c in
                c.compoundName.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "_", with: "-")
            }
        }()
        let perCompoundAnchors = compoundSlugs.flatMap { slug in
            ["protocol.compound.\(slug)", "protocol.compound.\(slug).dose"]
        }
        let allAnchors = ["today.macros", "today.schedule"] + perCompoundAnchors
        parts.append("""
        ## Tool Use Guidelines
        - For write tools (log_food_entry, log_dose, log_exercise_set, log_side_effect): always call the tool, the user will confirm before it's saved.
        - For search_food: call it automatically when you need accurate nutrition data, no confirmation needed.
        - When the user says "log X", use the appropriate tool. Don't ask for confirmation in your text response — the app will show a confirmation card.
        - After a tool is confirmed, acknowledge briefly and move on.

        ## Navigation + Spotlight
        - When the user asks to see something, navigate first with navigate_to_tab / open_compound / open_dosing_calculator / open_pinning_protocol. These take effect instantly.
        - After navigating, call spotlight_element with the anchor ID to draw a ring around the specific thing they asked about.
        - Keep spoken replies short (one sentence). The app is doing the navigation — you're just narrating.

        ## Registered anchor IDs (spotlight_element only works with these):
        \(allAnchors.map { "- \($0)" }.joined(separator: "\n"))
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Fetch helpers

    private static func fetchProfile(userId: String, context: ModelContext) -> CachedUserProfile? {
        let descriptor = FetchDescriptor<CachedUserProfile>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try? context.fetch(descriptor).first
    }

    private static func fetchProtocols(userId: String, context: ModelContext) -> [LocalProtocol] {
        let descriptor = FetchDescriptor<LocalProtocol>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchDoseLogs(userId: String, since: Date, context: ModelContext) -> [LocalDoseLog] {
        let descriptor = FetchDescriptor<LocalDoseLog>(
            predicate: #Predicate { $0.userId == userId && $0.dosedAt >= since },
            sortBy: [SortDescriptor(\.dosedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchFoodLogs(userId: String, since: Date, context: ModelContext) -> [LocalFoodLog] {
        let descriptor = FetchDescriptor<LocalFoodLog>(
            predicate: #Predicate { $0.userId == userId && $0.loggedAt >= since },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchSideEffects(userId: String, since: Date, context: ModelContext) -> [LocalSideEffectLog] {
        let descriptor = FetchDescriptor<LocalSideEffectLog>(
            predicate: #Predicate { $0.userId == userId && $0.loggedAt >= since },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchWorkouts(userId: String, since: Date, context: ModelContext) -> [LocalWorkout] {
        let descriptor = FetchDescriptor<LocalWorkout>(
            predicate: #Predicate { $0.userId == userId && $0.loggedAt >= since },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchExerciseLogs(userId: String, since: Date, context: ModelContext) -> [LocalExerciseLog] {
        let descriptor = FetchDescriptor<LocalExerciseLog>(
            predicate: #Predicate { $0.userId == userId && $0.loggedAt >= since },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
