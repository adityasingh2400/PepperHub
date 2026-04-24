import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var purchases: PurchasesManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nav: NavigationCoordinator
    @Environment(\.modelContext) private var ctx

    @Query private var activeProtocols: [LocalProtocol]
    @Query private var allFoodLogs: [LocalFoodLog]
    @Query private var allDoseLogs: [LocalDoseLog]
    @Query private var allWorkouts: [LocalWorkout]
    @Query private var allSideEffects: [LocalSideEffectLog]
    @Query private var allVials: [LocalVial]
    @Query private var timingRules: [CachedTimingRule]
    @Query private var profileCache: [CachedUserProfile]

    init(userId: String) {
        let uid = userId
        _activeProtocols = Query(filter: #Predicate<LocalProtocol> { $0.isActive == true && $0.userId == uid })
        _allFoodLogs = Query(filter: #Predicate<LocalFoodLog> { $0.userId == uid }, sort: \LocalFoodLog.loggedAt, order: .reverse)
        _allDoseLogs = Query(filter: #Predicate<LocalDoseLog> { $0.userId == uid }, sort: \LocalDoseLog.dosedAt, order: .reverse)
        _allWorkouts = Query(filter: #Predicate<LocalWorkout> { $0.userId == uid }, sort: \LocalWorkout.loggedAt, order: .reverse)
        _allSideEffects = Query(filter: #Predicate<LocalSideEffectLog> { $0.userId == uid }, sort: \LocalSideEffectLog.loggedAt, order: .reverse)
        _allVials = Query(filter: #Predicate<LocalVial> { $0.userId == uid })
        _profileCache = Query(filter: #Predicate<CachedUserProfile> { $0.userId == uid })
    }

    @State private var plan: PartitionPlan? = nil
    @State private var showQuickSideEffect = false
    @State private var showLogWorkout = false
    @State private var showLogFood = false
    @State private var showQuickDose = false

    var todayFood: [LocalFoodLog] {
        allFoodLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    var recentDoses: [LocalDoseLog] {
        allDoseLogs.filter { Calendar.current.isDateInToday($0.dosedAt) }
    }
    var todaySideEffects: [LocalSideEffectLog] {
        allSideEffects.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    var todayWorkouts: [LocalWorkout] {
        allWorkouts.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }
    var todayWorkout: LocalWorkout? { todayWorkouts.first }
    var todayCaloriesBurned: Int { todayWorkouts.reduce(0) { $0 + $1.caloriesBurned } }
    var activeVials: [LocalVial] {
        allVials.filter { $0.unitsRemaining > 0 }
    }
    var profile: CachedUserProfile? { profileCache.first }

    /// Compounds whose most recent dose is still inside the published
    /// duration window. Surfaced as a pill in the Today header so the user
    /// can tell at a glance what's circulating.
    var activeRightNow: [String] {
        guard let proto = activeProtocols.first else { return [] }
        let now = Date()
        var out: [String] = []
        var seen = Set<String>()
        for c in proto.compounds where !seen.contains(c.compoundName) {
            seen.insert(c.compoundName)
            guard let resolved = CompoundCatalog.compound(named: c.compoundName) else { continue }
            guard let lastDose = allDoseLogs.first(where: { $0.compoundName == c.compoundName })?.dosedAt else { continue }
            let elapsedHours = now.timeIntervalSince(lastDose) / 3600
            let duration = resolved.durationHours ?? 0
            if duration > 0, elapsedHours < duration {
                out.append(resolved.name)
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // 1. Greeting header + "active right now" pill
                    TodayHeader(activeNow: activeRightNow)

                    // 2. Quick actions
                    QuickActionsStrip(
                        onFood: { showLogFood = true },
                        onDose: { showQuickDose = true },
                        onWorkout: { showLogWorkout = true },
                        onSymptom: { showQuickSideEffect = true }
                    )

                    // 3. Macro ring
                    if let profile {
                        MacroRingCard(
                            logs: todayFood,
                            targetCalories: Int(profile.calorieTargetKcal > 0 ? profile.calorieTargetKcal : profile.tdeeKcal),
                            targetProtein: profile.macroGoalProteinG,
                            targetCarbs: profile.macroGoalCarbsG,
                            targetFat: profile.macroGoalFatG,
                            caloriesBurned: todayCaloriesBurned
                        )
                        .pepperAnchor("today.macros")
                    }

                    // 4. Today's meals
                    if !todayFood.isEmpty {
                        TodayMealsCard(logs: todayFood)
                    }

                    // 5. Dose schedule
                    if let proto = activeProtocols.first, !proto.compounds.isEmpty {
                        DoseScheduleCard(
                            compounds: proto.compounds,
                            loggedDoses: recentDoses
                        )
                        .pepperAnchor("today.schedule")
                    }

                    // 5b. Active compound timelines (where you are on the PK curve right now)
                    if let proto = activeProtocols.first, !proto.compounds.isEmpty {
                        ActiveCompoundTimelinesCard(
                            compounds: proto.compounds,
                            recentDoses: allDoseLogs
                        )
                    }

                    // 6. Partition Plan
                    if let profile {
                        let compounds = activeProtocols.first?.compounds ?? []
                        if purchases.isPro {
                            FullPartitionPlanCard(plan: plan, profile: profile, compounds: compounds)
                        } else {
                            FreePartitionPlanCard(plan: plan, profile: profile)
                        }
                    } else {
                        SetupProfileCTA()
                    }

                    // 7. Active vials
                    if !activeVials.isEmpty {
                        ActiveVialsCard(vials: activeVials)
                    }

                    // 8. Workout
                    WorkoutCard(workout: todayWorkout, onLog: { showLogWorkout = true })

                    // 9. Symptoms
                    TodaySymptomsCard(
                        symptoms: todaySideEffects,
                        onLogNew: { showQuickSideEffect = true }
                    )

                    // Bottom inset so the floating action stack
                    // (mic + Pepper bubble) never obscures real content.
                    Color.clear.frame(height: 96)
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView().environmentObject(authManager).environmentObject(purchases)) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color.appAccent)
                    }
                }
            }
            .sheet(isPresented: $appState.showSideEffectSheet) {
                SideEffectSheet(linkedDose: appState.recentDoseForSideEffect)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showQuickSideEffect) {
                SideEffectSheet(linkedDose: nil)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showLogWorkout) {
                LogWorkoutSheet(
                    onSave: { type, duration, notes, kcal in
                        guard let uid = authManager.session?.user.id.uuidString else { return }
                        let w = LocalWorkout(userId: uid, type: type, durationMinutes: duration, caloriesBurned: kcal, notes: notes)
                        ctx.insert(w)
                        try? ctx.save()
                        Task { await SyncService.shared.pushWorkout(w, context: ctx) }
                        Analytics.capture(.workoutLogged, properties: ["type": type, "duration_minutes": duration, "calories_burned": kcal])
                    },
                    weightKg: profile?.weightKg ?? 80
                )
            }
            .sheet(isPresented: $showLogFood) {
                ManualFoodEntrySheet(prefillName: "")
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showQuickDose) {
                QuickDoseLogSheet(
                    compounds: activeProtocols.first?.compounds ?? [],
                    vials: activeVials
                )
                .environmentObject(authManager)
                .environmentObject(appState)
            }
            .sheet(isPresented: $nav.showQuickDoseLog) {
                QuickDoseLogSheet(
                    compounds: activeProtocols.first?.compounds ?? [],
                    vials: activeVials
                )
                .environmentObject(authManager)
                .environmentObject(appState)
            }
            .task { await refreshPlan() }
            .onChange(of: activeProtocols.count) { _, _ in Task { await refreshPlan() } }
        }
    }

    private func refreshPlan() async {
        guard let profile else { return }
        let compounds = activeProtocols.first?.compounds ?? []
        plan = NudgeEngine.buildPlan(
            profile: profile,
            compounds: compounds,
            rules: timingRules,
            recentDoses: recentDoses,
            for: Date()
        )
    }
}

// MARK: - Macro Ring Card

struct MacroRingCard: View {
    let logs: [LocalFoodLog]
    let targetCalories: Int
    let targetProtein: Int
    let targetCarbs: Int
    let targetFat: Int
    var caloriesBurned: Int = 0

    var totalKcal: Int       { logs.reduce(0) { $0 + $1.kcal } }
    var totalProtein: Double { logs.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double   { logs.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double     { logs.reduce(0) { $0 + $1.fatG } }

    var adjustedTarget: Int { targetCalories + caloriesBurned }
    var calPct: Double { adjustedTarget > 0 ? min(1, Double(totalKcal) / Double(adjustedTarget)) : 0 }
    var proteinPct: Double { targetProtein > 0 ? min(1, totalProtein / Double(targetProtein)) : 0 }
    var carbsPct: Double   { targetCarbs > 0 ? min(1, totalCarbs / Double(targetCarbs)) : 0 }
    var fatPct: Double     { targetFat > 0 ? min(1, totalFat / Double(targetFat)) : 0 }
    var remaining: Int { adjustedTarget - totalKcal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY'S INTAKE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .kerning(1.2)
                Spacer()
                if caloriesBurned > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "ea580c"))
                        Text("+\(caloriesBurned) burned")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "ea580c"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "fff7ed"))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            HStack(spacing: 20) {
                // Calorie ring
                ZStack {
                    Circle()
                        .stroke(Color.appDivider, lineWidth: 10)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: calPct)
                        .stroke(caloriesBurned > 0 ? Color(hex: "ea580c") : Color.appAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: calPct)
                    VStack(spacing: 1) {
                        Text("\(totalKcal)")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(Color.appTextPrimary)
                        Text("/ \(adjustedTarget)")
                            .font(.system(size: 10))
                            .foregroundColor(Color.appTextMeta)
                        Text("\(max(0, remaining)) left")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(remaining < 0 ? Color(hex: "dc2626") : Color.appTextMeta)
                    }
                }

                // Macro bars
                VStack(spacing: 10) {
                    MacroBarRow(label: "Protein", current: Int(totalProtein), target: targetProtein, unit: "g", color: Color(hex: "3b82f6"))
                    MacroBarRow(label: "Carbs",   current: Int(totalCarbs),   target: targetCarbs,   unit: "g", color: Color(hex: "f59e0b"))
                    MacroBarRow(label: "Fat",     current: Int(totalFat),     target: targetFat,     unit: "g", color: Color(hex: "ec4899"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct MacroBarRow: View {
    let label: String
    let current: Int
    let target: Int
    let unit: String
    let color: Color

    var pct: Double { target > 0 ? min(1, Double(current) / Double(target)) : 0 }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
                Text("\(current)/\(target)\(unit)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appDivider).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(pct), height: 5)
                        .animation(.easeInOut(duration: 0.6), value: pct)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Dose Schedule Card

struct DoseScheduleCard: View {
    let compounds: [LocalProtocolCompound]
    let loggedDoses: [LocalDoseLog]

    private struct ScheduledDose: Identifiable {
        let id = UUID()
        let compound: String
        let doseMcg: Double
        let time: Date
        var isDone: Bool
    }

    private var scheduledDoses: [ScheduledDose] {
        var doses: [ScheduledDose] = []
        let cal = Calendar.current
        let today = Date()

        for compound in compounds {
            guard shouldDoseToday(compound: compound) else { continue }
            for timeStr in compound.doseTimes {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                guard let doseDate = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: today) else { continue }

                let isDone = loggedDoses.contains { log in
                    log.compoundName == compound.compoundName &&
                    abs(log.dosedAt.timeIntervalSince(doseDate)) < 3600
                }
                doses.append(ScheduledDose(compound: compound.compoundName, doseMcg: compound.doseMcg, time: doseDate, isDone: isDone))
            }
        }
        return doses.sorted { $0.time < $1.time }
    }

    private func shouldDoseToday(compound: LocalProtocolCompound) -> Bool {
        switch compound.frequency {
        case "daily": return true
        case "eod":
            let daysSinceEpoch = Int(Date().timeIntervalSince1970 / 86400)
            return daysSinceEpoch % 2 == 0
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODAY'S DOSES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .kerning(1.2)
                Spacer()
                let doneCount = scheduledDoses.filter(\.isDone).count
                if !scheduledDoses.isEmpty {
                    Text("\(doneCount)/\(scheduledDoses.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(doneCount == scheduledDoses.count ? Color(hex: "16a34a") : Color.appTextMeta)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if scheduledDoses.isEmpty {
                Text("No doses scheduled today")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextMeta)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(scheduledDoses.enumerated()), id: \.element.id) { idx, dose in
                        DoseTimelineRow(
                            isLast: idx == scheduledDoses.count - 1,
                            compound: dose.compound,
                            doseMcg: dose.doseMcg,
                            time: dose.time,
                            isDone: dose.isDone
                        )
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct DoseTimelineRow: View {
    let isLast: Bool
    let compound: String
    let doseMcg: Double
    let time: Date
    let isDone: Bool

    var isUpcoming: Bool { !isDone && time > Date() }
    var isPast: Bool { !isDone && time <= Date() }

    var body: some View {
        HStack(spacing: 14) {
            // Timeline dot + line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color(hex: "16a34a") : isUpcoming ? Color.appAccent : Color.appBorder)
                        .frame(width: 20, height: 20)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .fill(Color.appCard)
                            .frame(width: 8, height: 8)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.appBorder)
                        .frame(width: 2, height: 28)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compound)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDone ? Color.appTextTertiary : Color.appTextPrimary)
                    Text("\(Int(doseMcg)) mcg")
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextMeta)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(time.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDone ? Color.appTextMeta : isUpcoming ? Color.appAccent : Color.appTextTertiary)
                    if isPast {
                        Text("missed?")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "f59e0b"))
                    } else if isDone {
                        Text("done")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "16a34a"))
                    } else {
                        Text("upcoming")
                            .font(.system(size: 10))
                            .foregroundColor(Color.appTextMeta)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isLast ? 8 : 4)
    }
}

// MARK: - Workout Card

struct WorkoutCard: View {
    let workout: LocalWorkout?
    let onLog: () -> Void

    private let typeIcons: [String: String] = [
        "strength": "dumbbell.fill",
        "cardio": "figure.run",
        "hiit": "bolt.fill",
        "mobility": "figure.flexibility",
        "sport": "sportscourt.fill",
        "other": "figure.mixed.cardio"
    ]

    var body: some View {
        if let workout {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.appAccentTint)
                        .frame(width: 44, height: 44)
                    Image(systemName: typeIcons[workout.type] ?? "figure.mixed.cardio")
                        .font(.system(size: 18))
                        .foregroundColor(Color.appAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.type.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary)
                    HStack(spacing: 6) {
                        Text("\(workout.durationMinutes) min\(workout.notes.isEmpty ? "" : " · \(workout.notes)")")
                            .font(.system(size: 12))
                            .foregroundColor(Color.appTextTertiary)
                            .lineLimit(1)
                        if workout.caloriesBurned > 0 {
                            Text("· \(workout.caloriesBurned) kcal burned")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "ea580c"))
                        }
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "16a34a"))
            }
            .padding(14)
            .background(Color.appCard)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
        } else {
            Button(action: onLog) {
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.appTextMeta)
                    Text("Log today's workout")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary)
                    Spacer()
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color.appAccent)
                }
                .padding(14)
                .background(Color.appCard)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }
}

// MARK: - Log Workout Sheet

struct LogWorkoutSheet: View {
    let onSave: (String, Int, String, Int) -> Void
    var weightKg: Double = 80
    @Environment(\.dismiss) private var dismiss

    private let types = ["strength", "cardio", "hiit", "mobility", "sport", "other"]
    private let typeLabels = ["Strength", "Cardio", "HIIT", "Mobility", "Sport", "Other"]
    private let typeIcons = ["dumbbell.fill", "figure.run", "bolt.fill", "figure.flexibility", "sportscourt.fill", "figure.mixed.cardio"]
    private let typeMETs: [String: Double] = [
        "strength": 3.5, "cardio": 7.0, "hiit": 8.0,
        "mobility": 2.5, "sport": 6.5, "other": 5.0
    ]

    @State private var selectedType = "strength"
    @State private var duration = 45
    @State private var caloriesBurned = 0
    @State private var caloriesEdited = false
    @State private var notes = ""

    private func estimatedCalories(type: String, minutes: Int) -> Int {
        let met = typeMETs[type] ?? 5.0
        return Int(met * weightKg * (Double(minutes) / 60.0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Type grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TYPE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(types.enumerated()), id: \.offset) { idx, type in
                                Button {
                                    selectedType = type
                                    if !caloriesEdited {
                                        caloriesBurned = estimatedCalories(type: type, minutes: duration)
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: typeIcons[idx])
                                            .font(.system(size: 20))
                                            .foregroundColor(selectedType == type ? Color.appAccent : Color.appTextTertiary)
                                        Text(typeLabels[idx])
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(selectedType == type ? Color.appAccent : Color.appTextSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(selectedType == type ? Color.appAccentTint : Color.white)
                                    .cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(selectedType == type ? Color.appAccent : Color.appBorder, lineWidth: selectedType == type ? 2 : 1.5))
                                }
                            }
                        }
                    }

                    // Duration stepper
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DURATION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        HStack {
                            Button {
                                if duration > 5 {
                                    duration -= 5
                                    if !caloriesEdited { caloriesBurned = estimatedCalories(type: selectedType, minutes: duration) }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color.appAccent)
                            }
                            Spacer()
                            Text("\(duration) min")
                                .font(.system(size: 32, weight: .black))
                                .foregroundColor(Color.appTextPrimary)
                            Spacer()
                            Button {
                                duration += 5
                                if !caloriesEdited { caloriesBurned = estimatedCalories(type: selectedType, minutes: duration) }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color.appAccent)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Calories burned
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CALORIES BURNED")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                            Spacer()
                            if caloriesEdited {
                                Button("Reset estimate") {
                                    caloriesBurned = estimatedCalories(type: selectedType, minutes: duration)
                                    caloriesEdited = false
                                }
                                .font(.system(size: 11))
                                .foregroundColor(Color.appAccent)
                            }
                        }
                        HStack {
                            Button {
                                if caloriesBurned >= 10 {
                                    caloriesBurned -= 10
                                    caloriesEdited = true
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(hex: "ea580c"))
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Text("\(caloriesBurned)")
                                    .font(.system(size: 32, weight: .black))
                                    .foregroundColor(caloriesBurned > 0 ? Color(hex: "ea580c") : Color.appTextMeta)
                                Text("kcal")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.appTextMeta)
                            }
                            Spacer()
                            Button {
                                caloriesBurned += 10
                                caloriesEdited = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(hex: "ea580c"))
                            }
                        }
                        .padding(.horizontal, 20)
                        if !caloriesEdited {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.appTextMeta)
                                Text("Estimated from workout type, duration, and your weight")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.appTextMeta)
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOTES (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        TextField("e.g. Upper body push day, PR on bench", text: $notes)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1.5))
                    }

                    Button {
                        onSave(selectedType, duration, notes, caloriesBurned)
                        dismiss()
                    } label: {
                        Text("Log Workout")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.appAccent)
                            .cornerRadius(14)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Today's Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.appAccent)
                }
            }
        }
        .onAppear {
            caloriesBurned = estimatedCalories(type: selectedType, minutes: duration)
        }
    }
}

// MARK: - Full Partition Plan Card (Pro)

struct FullPartitionPlanCard: View {
    let plan: PartitionPlan?
    let profile: CachedUserProfile
    let compounds: [LocalProtocolCompound]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S PARTITION PLAN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.2)
                    if let plan, !plan.activeCompounds.isEmpty {
                        Text(plan.activeCompounds.joined(separator: " + "))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                    } else {
                        Text("No active protocol")
                            .font(.system(size: 15))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
                Spacer()
                Text(Date().formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextMeta)
            }
            .padding(16)

            if let plan, let nextDose = plan.nextDoseAt {
                Divider().overlay(Color.appDivider)
                NextDoseRow(compound: plan.nextDoseCompound ?? "", at: nextDose, preWindowStart: plan.preWindowStartsAt)
            }

            if let warning = plan?.restrictionWarning {
                RestrictionBanner(text: warning)
            }

            Divider().overlay(Color.appDivider)
            HStack {
                MacroTotalChip(value: "\(plan?.dailyProteinG ?? profile.macroGoalProteinG)g", label: "Protein", color: Color(hex: "1d4ed8"))
                MacroTotalChip(value: "\(plan?.dailyCarbsG ?? profile.macroGoalCarbsG)g",   label: "Carbs",   color: Color(hex: "b45309"))
                MacroTotalChip(value: "\(plan?.dailyFatG ?? profile.macroGoalFatG)g",       label: "Fat",     color: Color(hex: "9d174d"))
                MacroTotalChip(value: "\(plan?.tdeeKcal ?? Int(profile.calorieTargetKcal > 0 ? profile.calorieTargetKcal : profile.tdeeKcal))", label: "kcal", color: Color.appTextPrimary)
            }
            .padding(16)

            if let plan, !plan.windows.isEmpty {
                Divider().overlay(Color.appDivider)
                VStack(spacing: 0) {
                    HStack {
                        Text("Window").frame(maxWidth: .infinity, alignment: .leading)
                        Text("P").frame(width: 36, alignment: .trailing)
                        Text("C").frame(width: 40, alignment: .trailing)
                        Text("F").frame(width: 32, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ForEach(plan.windows.filter { $0.type != .dose }, id: \.label) { window in
                        MealWindowRow(window: window)
                        if window.label != plan.windows.filter({ $0.type != .dose }).last?.label {
                            Divider().overlay(Color.appDivider).padding(.leading, 16)
                        }
                    }
                }
            }

            Divider().overlay(Color.appDivider)
            Text("Estimates only · Not medical advice")
                .font(.system(size: 10))
                .foregroundColor(Color.appTextMeta)
                .padding(10)
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

struct MealWindowRow: View {
    let window: MealWindow

    var body: some View {
        HStack {
            Text("\(window.emoji) \(window.label)")
                .font(.system(size: 12))
                .foregroundColor(window.isRestricted ? Color(hex: "92400e") : Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(window.proteinG)g").frame(width: 36, alignment: .trailing)
            Text("\(window.carbsG)g").frame(width: 40, alignment: .trailing)
            Text("\(window.fatG)g").frame(width: 32, alignment: .trailing)
        }
        .font(.system(size: 12))
        .foregroundColor(window.isRestricted ? Color(hex: "92400e") : Color.appTextSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(window.isRestricted ? Color(hex: "fff8ee") : Color.clear)
    }
}

// MARK: - Free Partition Plan Card

struct FreePartitionPlanCard: View {
    let plan: PartitionPlan?
    let profile: CachedUserProfile
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S PARTITION PLAN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.2)
                    if let plan, !plan.activeCompounds.isEmpty {
                        Text(plan.activeCompounds.joined(separator: " + "))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                    } else {
                        Text("No active protocol")
                            .font(.system(size: 15))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
                Spacer()
            }
            .padding(16)

            if let plan, let nextDose = plan.nextDoseAt {
                Divider().overlay(Color.appDivider)
                NextDoseRow(compound: plan.nextDoseCompound ?? "", at: nextDose, preWindowStart: plan.preWindowStartsAt)
            }

            if let warning = plan?.restrictionWarning {
                RestrictionBanner(text: warning)
            }

            Divider().overlay(Color.appDivider)
            HStack {
                MacroTotalChip(value: "\(plan?.dailyProteinG ?? profile.macroGoalProteinG)g", label: "Protein", color: Color(hex: "1d4ed8"))
                MacroTotalChip(value: "\(plan?.dailyCarbsG ?? profile.macroGoalCarbsG)g",   label: "Carbs",   color: Color(hex: "b45309"))
                MacroTotalChip(value: "\(plan?.dailyFatG ?? profile.macroGoalFatG)g",       label: "Fat",     color: Color(hex: "9d174d"))
                MacroTotalChip(value: "\(plan?.tdeeKcal ?? Int(profile.calorieTargetKcal > 0 ? profile.calorieTargetKcal : profile.tdeeKcal))", label: "kcal", color: Color.appTextPrimary)
            }
            .padding(16)

            Divider().overlay(Color.appDivider)
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Text("Window").frame(maxWidth: .infinity, alignment: .leading)
                        Text("P").frame(width: 36, alignment: .trailing)
                        Text("C").frame(width: 40, alignment: .trailing)
                        Text("F").frame(width: 32, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .padding(.horizontal, 16).padding(.vertical, 8)

                    ForEach(["🌅 Morning","⚡ Pre-dose","🔄 Post-dose"], id: \.self) { w in
                        HStack {
                            Text(w).font(.system(size: 12)).foregroundColor(Color.appTextTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("55g").frame(width: 36, alignment: .trailing)
                            Text("120g").frame(width: 40, alignment: .trailing)
                            Text("30g").frame(width: 32, alignment: .trailing)
                        }
                        .font(.system(size: 12)).foregroundColor(Color.appTextSecondary)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                    }
                }
                .blur(radius: 4).opacity(0.4)

                VStack(spacing: 6) {
                    Text("See your full meal windows")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(Color.appTextPrimary)
                    Text("Know exactly how much to eat around each dose")
                        .font(.system(size: 11)).foregroundColor(Color.appTextTertiary).multilineTextAlignment(.center)
                    Button(action: { showPaywall = true }) {
                        Text("Start 7-Day Free Trial")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 9)
                            .background(Color.appAccent).cornerRadius(20)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 12)

            Divider().overlay(Color.appDivider)
            Text("Estimates only · Not medical advice")
                .font(.system(size: 10)).foregroundColor(Color.appTextMeta).padding(10)
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showPaywall) { ProPaywallView() }
    }
}

// MARK: - Shared components

struct NextDoseRow: View {
    let compound: String
    let at: Date
    let preWindowStart: Date?

    var timeUntil: String {
        let secs = at.timeIntervalSinceNow
        guard secs > 0 else { return "Now" }
        let h = Int(secs / 3600)
        let m = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeUntil)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.appAccent)
                Text("until next dose")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "be123c"))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(at.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Text(compound)
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
            }
        }
        .padding(16)
        .background(Color.appAccentTint)
    }
}

struct RestrictionBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "92400e"))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "92400e"))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: "fff8ee"))
        .overlay(Divider().overlay(Color(hex: "fde68a")), alignment: .bottom)
    }
}

struct SetupProfileCTA: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.system(size: 40))
                .foregroundColor(Color.appBorder)
            Text("Set up your profile")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
            Text("Add your body stats to unlock your Partition Plan and macro targets.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct MacroTotalChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .black)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(Color.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Today Header

struct TodayHeader: View {
    var activeNow: [String] = []

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text(dateString)
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextMeta)
                }
                Spacer()
            }

            if !activeNow.isEmpty {
                ActiveRightNowPill(compoundNames: activeNow)
            }
        }
        .padding(.top, 4)
    }
}

/// Tiny capsule that lists the compounds currently inside their duration
/// window. Calm visual — doesn't compete with the headline, but is the first
/// thing the user reads on a glance.
struct ActiveRightNowPill: View {
    let compoundNames: [String]

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 7, height: 7)
                Circle()
                    .stroke(Color.appAccent.opacity(0.4), lineWidth: 6)
                    .frame(width: 7, height: 7)
                    .blur(radius: 4)
            }
            Text("Active in your system")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.appTextSecondary)
                .kerning(0.4)
            Text("·")
                .foregroundColor(Color.appTextMeta)
            Text(compoundNames.prefix(3).joined(separator: ", "))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color.appAccent)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.appAccentTint)
                .overlay(
                    Capsule().stroke(Color.appAccent.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Quick Actions Strip

struct QuickActionsStrip: View {
    let onFood: () -> Void
    let onDose: () -> Void
    let onWorkout: () -> Void
    let onSymptom: () -> Void

    private struct Action {
        let label: String
        let icon: String
        let color: Color
        let tint: Color
        let action: () -> Void
    }

    var body: some View {
        let actions: [Action] = [
            Action(label: "Food", icon: "fork.knife", color: Color(hex: "b45309"), tint: Color(hex: "fef3c7"), action: onFood),
            Action(label: "Dose", icon: "drop.fill", color: Color.appAccent, tint: Color.appAccentTint, action: onDose),
            Action(label: "Workout", icon: "dumbbell.fill", color: Color(hex: "1d4ed8"), tint: Color(hex: "eff6ff"), action: onWorkout),
            Action(label: "Symptom", icon: "heart.text.square.fill", color: Color(hex: "059669"), tint: Color(hex: "d1fae5"), action: onSymptom),
        ]
        HStack(spacing: 10) {
            ForEach(actions, id: \.label) { a in
                Button(action: a.action) {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(a.tint)
                                .frame(width: 48, height: 48)
                            Image(systemName: a.icon)
                                .font(.system(size: 18))
                                .foregroundColor(a.color)
                        }
                        Text(a.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Today's Meals Card

struct TodayMealsCard: View {
    let logs: [LocalFoodLog]

    private var grouped: [(String, [LocalFoodLog])] {
        let order = ["pre_dose", "post_dose", "free"]
        let labels = ["pre_dose": "Pre-Dose", "post_dose": "Post-Dose", "free": "Other"]
        let dict = Dictionary(grouping: logs, by: \.mealWindow)
        return order.compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (labels[key] ?? key, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY'S MEALS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .kerning(1.2)
                Spacer()
                Text("\(logs.count) item\(logs.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(grouped, id: \.0) { label, items in
                VStack(alignment: .leading, spacing: 0) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                    ForEach(items) { log in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.appDivider)
                                .frame(width: 6, height: 6)
                            Text(log.foodName)
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(log.kcal) kcal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.appTextTertiary)
                            Text("· \(Int(log.proteinG))g P")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "3b82f6"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        Divider()
                            .overlay(Color.appDivider)
                            .padding(.leading, 32)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Active Vials Card

struct ActiveVialsCard: View {
    let vials: [LocalVial]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIALS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)

            ForEach(vials) { vial in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccentTint)
                            .frame(width: 36, height: 36)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.appAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vial.compoundName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary)
                        Text(String(format: "%.0f mcg/unit · %.1f units left", vial.concentrationMcgPerUnit, vial.unitsRemaining))
                            .font(.system(size: 11))
                            .foregroundColor(Color.appTextMeta)
                    }
                    Spacer()
                    VialGaugeView(pct: vial.percentRemaining)
                }
                if vial.id != vials.last?.id {
                    Divider().overlay(Color.appDivider)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct VialGaugeView: View {
    let pct: Double

    private var color: Color {
        if pct > 0.5 { return Color(hex: "16a34a") }
        if pct > 0.2 { return Color(hex: "f59e0b") }
        return Color(hex: "dc2626")
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.appDivider, lineWidth: 4)
                    .frame(width: 34, height: 34)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Today's Symptoms Card

struct TodaySymptomsCard: View {
    let symptoms: [LocalSideEffectLog]
    let onLogNew: () -> Void

    private let severityColors: [Color] = [
        Color(hex: "16a34a"),
        Color(hex: "65a30d"),
        Color(hex: "f59e0b"),
        Color(hex: "ea580c"),
        Color(hex: "dc2626")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOW DO YOU FEEL?")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
                    .kerning(1.2)
                Spacer()
                Button(action: onLogNew) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Log")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccentTint)
                    .cornerRadius(8)
                }
            }

            if symptoms.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "16a34a"))
                    Text("No symptoms logged today")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextTertiary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(symptoms) { s in
                        HStack(spacing: 10) {
                            let clampedSev = max(0, min(4, s.severity - 1))
                            Circle()
                                .fill(severityColors[clampedSev])
                                .frame(width: 8, height: 8)
                            Text(s.symptom)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary)
                            Spacer()
                            Text("Severity \(s.severity)/5")
                                .font(.system(size: 11))
                                .foregroundColor(Color.appTextMeta)
                            Text(s.loggedAt, format: .dateTime.hour().minute())
                                .font(.system(size: 11))
                                .foregroundColor(Color.appTextMeta)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Quick Dose Log Sheet

struct QuickDoseLogSheet: View {
    let compounds: [LocalProtocolCompound]
    let vials: [LocalVial]

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var loggingId: UUID? = nil
    @State private var doneIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if compounds.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color.appBorder)
                        Text("No active protocol")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                        Text("Set up a protocol in the Protocol tab first.")
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground.ignoresSafeArea())
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(compounds) { compound in
                                let isDone = doneIds.contains(compound.id)
                                let isLogging = loggingId == compound.id

                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(isDone ? Color(hex: "dcfce7") : Color.appAccentTint)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: isDone ? "checkmark" : "drop.fill")
                                            .font(.system(size: 16, weight: isDone ? .bold : .regular))
                                            .foregroundColor(isDone ? Color(hex: "16a34a") : Color.appAccent)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(compound.compoundName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(isDone ? Color.appTextTertiary : Color.appTextPrimary)
                                        Text("\(Int(compound.doseMcg)) mcg · \(compound.frequency)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.appTextMeta)
                                    }

                                    Spacer()

                                    if isDone {
                                        Text("Logged")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color(hex: "16a34a"))
                                    } else {
                                        Button {
                                            quickLog(compound)
                                        } label: {
                                            Group {
                                                if isLogging {
                                                    ProgressView().tint(.white)
                                                } else {
                                                    Text("Log Now")
                                                        .font(.system(size: 13, weight: .bold))
                                                }
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 9)
                                            .background(Color.appAccent)
                                            .cornerRadius(10)
                                        }
                                        .disabled(isLogging)
                                    }
                                }
                                .padding(14)
                                .background(Color.appCard)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isDone ? Color(hex: "bbf7d0") : Color.appBorder, lineWidth: 1))
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.appBackground.ignoresSafeArea())
                }
            }
            .navigationTitle("Quick Log Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.appAccent)
                }
            }
        }
    }

    private func quickLog(_ compound: LocalProtocolCompound) {
        guard let uid = authManager.session?.user.id.uuidString else { return }
        loggingId = compound.id
        let vial = vials.first { $0.compoundName == compound.compoundName }
        let log = LocalDoseLog(
            userId: uid,
            compoundName: compound.compoundName,
            doseMcg: compound.doseMcg,
            injectionSite: "Left Abdomen"
        )
        log.vialId = vial?.id
        if let vial {
            let unitsUsed = compound.doseMcg / vial.concentrationMcgPerUnit
            vial.unitsRemaining = max(0, vial.unitsRemaining - unitsUsed)
        }
        ctx.insert(log)
        try? ctx.save()
        Analytics.capture(.doseLogged, properties: ["compound": compound.compoundName, "dose_mcg": compound.doseMcg, "source": "quick_log"])
        let vialToSync = vial
        Task {
            await SyncService.shared.pushDoseLog(log, context: ctx)
            if let v = vialToSync {
                await SyncService.shared.pushVial(v, context: ctx)
            }
            await MainActor.run {
                loggingId = nil
                doneIds.insert(compound.id)
                appState.recentDoseForSideEffect = log
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    appState.showSideEffectSheet = true
                }
            }
        }
    }
}

// MARK: - Active Compound Timelines Card

/// "Where you are on the curve right now" — Today's hero card for active
/// peptides. Each row pairs the compound's pharmacokinetic curve with the
/// time elapsed since the most recent dose, so the user instantly knows
/// whether they're on the rise, peaking, or decaying.
///
/// Tapping a row opens that compound's detail page (with the expanded
/// timeline + dosing/pinning shortcuts).
struct ActiveCompoundTimelinesCard: View {
    let compounds: [LocalProtocolCompound]
    let recentDoses: [LocalDoseLog]

    @EnvironmentObject private var nav: NavigationCoordinator

    private struct Row: Identifiable {
        let id = UUID()
        let compound: Compound
        let lastDosedAt: Date?
    }

    private var rows: [Row] {
        // De-duplicate by compound name, then resolve against the catalog and pull the most recent dose.
        var seen = Set<String>()
        var out: [Row] = []
        for c in compounds where !seen.contains(c.compoundName) {
            seen.insert(c.compoundName)
            guard let resolved = CompoundCatalog.compound(named: c.compoundName) else { continue }
            guard resolved.timeline.hasAnyData else { continue }
            let lastDose = recentDoses
                .filter { $0.compoundName == c.compoundName }
                .max(by: { $0.dosedAt < $1.dosedAt })
                .map(\.dosedAt)
            out.append(Row(compound: resolved, lastDosedAt: lastDose))
        }
        return out
    }

    var body: some View {
        guard !rows.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("COMPOUND ACTIVITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        Text("Live curves anchored to your last dose")
                            .font(.system(size: 11))
                            .foregroundColor(Color.appTextMeta)
                    }
                    Spacer()
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.appAccent)
                }

                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        compoundRow(row)
                    }
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }

    private func compoundRow(_ row: Row) -> some View {
        Button {
            nav.openCompound(row.compound)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(row.compound.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    if let phase = phaseLabel(for: row) {
                        Text(phase.text)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(phase.color))
                    }
                    Spacer()
                    if let lastDose = row.lastDosedAt {
                        Text(relativeLabel(for: lastDose))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.appTextTertiary)
                    } else {
                        Text("No doses yet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.appTextMeta)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                }

                PeptideTimelineView(
                    timeline: row.compound.timeline,
                    mode: .compact,
                    dosedAt: row.lastDosedAt
                )
            }
        }
        .buttonStyle(.plain)
    }

    private struct Phase { let text: String; let color: Color }

    /// Map elapsed-time-into-curve into a human label so even glance-readers
    /// know whether the compound is climbing, peaking, or fading.
    private func phaseLabel(for row: Row) -> Phase? {
        guard let lastDose = row.lastDosedAt else { return nil }
        let elapsedHours = Date().timeIntervalSince(lastDose) / 3600
        let onset    = row.compound.timeToEffectHours ?? 0
        let peak     = row.compound.peakEffectHours   ?? 0
        let duration = row.compound.durationHours     ?? 0

        if elapsedHours < onset {
            return Phase(text: "Onset", color: Color.appAccent.opacity(0.6))
        }
        if peak > 0, elapsedHours < peak * 1.1 {
            return Phase(text: "Peaking", color: Color.appAccent)
        }
        if duration > 0, elapsedHours < duration {
            return Phase(text: "Decaying", color: Color(hex: "f59e0b"))
        }
        return Phase(text: "Cleared", color: Color.appTextMeta)
    }

    private func relativeLabel(for date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let h = elapsed / 3600
        if h < 1 { return "Dosed \(Int(elapsed / 60))m ago" }
        if h < 24 { return "Dosed \(Int(h))h ago" }
        let days = h / 24
        return "Dosed \(Int(days))d ago"
    }
}

// MacroProgressCard kept for backward compat with any other callers
struct MacroProgressCard: View {
    let logs: [LocalFoodLog]
    let targetProtein: Int
    let targetCarbs: Int
    let targetFat: Int
    let targetKcal: Int

    var body: some View {
        MacroRingCard(
            logs: logs,
            targetCalories: targetKcal,
            targetProtein: targetProtein,
            targetCarbs: targetCarbs,
            targetFat: targetFat
        )
    }
}
