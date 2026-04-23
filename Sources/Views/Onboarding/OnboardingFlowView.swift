import SwiftUI

// MARK: - ViewModel

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step = 1  // 1-12 (peptide goals → fitness → stats → protocol → numbers → trial)

    // Step 1 — Goal
    @Published var goal: Goal = .recomp

    // Step 2 — Experience
    @Published var experience: Experience = .some

    // Step 3 — Biological Sex
    @Published var biologicalSex: BiologicalSex = .male

    // Step 4 — Age
    @Published var age: Int = 28

    // Step 5 — Height
    @Published var heightCm: Double = 175
    @Published var useImperial = false

    // Step 6 — Weight
    @Published var weightKg: Double = 80

    // Step 7 — Activity Level
    @Published var activityLevel: ActivityLevel = .moderate

    // Step 8 — Training days/week
    @Published var trainingDaysPerWeek: Int = 3

    // Step 9 — Training time
    @Published var trainingTime: TrainingTime = .varies

    // Step 10 — Eating style
    @Published var eatingStyle: EatingStyle = .standard

    // Step 11 — Meals per day
    @Published var mealsPerDay: Int = 3

    // Step 12 — Protocol
    @Published var hasProtocol = false
    @Published var selectedCompounds: Set<String> = []
    /// What the user wants from peptides. Used to recommend compounds in the picker.
    @Published var peptideGoals: Set<String> = []

    static let commonCompounds: [String] = [
        "BPC-157", "TB-500", "CJC-1295", "Ipamorelin", "GHRP-2", "GHRP-6",
        "Sermorelin", "Tesamorelin", "AOD-9604", "Semaglutide", "Tirzepatide",
        "PT-141", "Melanotan II", "Thymosin Alpha-1", "GHK-Cu", "MK-677",
        "Hexarelin", "Selank", "Semax",
    ]

    /// Compounds whose `goal_categories` overlap any of the user's selected peptide goals.
    /// Sorted by overlap count (descending), then alphabetically. Used by the picker to
    /// surface a "Recommended for you" row.
    var recommendedCompounds: [Compound] {
        guard !peptideGoals.isEmpty else { return [] }
        let scored = Compound.seedData.compactMap { c -> (Compound, Int)? in
            let overlap = c.goalCategories.filter(peptideGoals.contains).count
            return overlap > 0 ? (c, overlap) : nil
        }
        return scored.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name < $1.0.name
        }.map(\.0)
    }

    // Kept for backward compat with OnboardingTrialView / MacroMode
    @Published var macroMode: MacroMode = .auto

    // Step 13 — AI nutrition plan (nil = use formula fallback)
    @Published var nutritionPlan: NutritionPlan? = nil
    @Published var isLoadingPlan = false
    @Published var planLoadError: String? = nil

    // MARK: - NutritionPlan model

    struct NutritionPlan: Codable {
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let overallRationale: String
        let caloriesExplanation: String
        let proteinExplanation: String
        let carbsExplanation: String
        let fatExplanation: String
    }

    // MARK: - Fetch AI nutrition plan from edge function

    func fetchNutritionPlan() async {
        isLoadingPlan = true
        planLoadError = nil

        defer { isLoadingPlan = false }

        do {
            guard let url = URL(string: "https://sgbszuimvqxzqvmgvyrn.supabase.co/functions/v1/nutrition-plan") else { return }

            guard let session = try? await supabase.auth.session else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "goal": goal.rawValue,
                "experience": experience.rawValue,
                "biologicalSex": biologicalSex.rawValue,
                "age": age,
                "heightCm": heightCm,
                "weightKg": weightKg,
                "activityLevel": activityLevel.rawValue,
                "trainingDaysPerWeek": trainingDaysPerWeek,
                "trainingTime": trainingTime.rawValue,
                "eatingStyle": eatingStyle.rawValue,
                "mealsPerDay": mealsPerDay,
                "hasProtocol": hasProtocol,
                "compounds": Array(selectedCompounds).sorted(),
                "baselineCalories": Int(calorieTarget),
                "baselineProteinG": proteinG,
                "baselineCarbsG": carbsG,
                "baselineFatG": fatG,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let plan = try JSONDecoder().decode(NutritionPlan.self, from: data)
            nutritionPlan = plan
        } catch {
            planLoadError = "Couldn't load AI plan — using calculated targets."
        }
    }

    // MARK: - Computed: RMR (Mifflin-St Jeor)

    var rmr: Double {
        let sexOffset: Double
        switch biologicalSex {
        case .male:   sexOffset = 5
        case .female: sexOffset = -161
        case .other:  sexOffset = -78
        }
        return (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + sexOffset
    }

    // MARK: - TDEE

    var tdee: Double {
        let base = rmr * activityLevel.multiplier
        let trainingBonus = Double(trainingDaysPerWeek) * 40
        return base + trainingBonus
    }

    // MARK: - Calorie target

    var calorieTarget: Double {
        switch goal {
        case .recomp:    return tdee * 1.00
        case .bulk:      return tdee * 1.10
        case .cut:       return tdee * 0.85
        case .antiAging: return tdee * 0.90
        }
    }

    // MARK: - Protein

    var proteinG: Int {
        var perKg = 2.0
        switch goal {
        case .cut:      perKg += 0.4
        case .bulk:     perKg += 0.2
        case .recomp:   perKg += 0.1
        case .antiAging: perKg -= 0.1
        }
        switch biologicalSex {
        case .male:  perKg += 0.2
        case .female: perKg -= 0.2
        case .other: break
        }
        switch experience {
        case .veteran: perKg += 0.2
        case .new:     perKg -= 0.1
        case .some:    break
        }
        if trainingDaysPerWeek >= 5 { perKg += 0.1 }
        return Int(weightKg * max(1.4, perKg))
    }

    // MARK: - Fat

    var fatG: Int {
        var perKg: Double
        switch eatingStyle {
        case .standard:             perKg = 0.8
        case .lowCarb:              perKg = 1.3
        case .highCarb:             perKg = 0.5
        case .intermittentFasting:  perKg = 1.0
        }
        if biologicalSex == .female { perKg += 0.1 }
        return Int(weightKg * perKg)
    }

    // MARK: - Carbs

    var carbsG: Int {
        let remaining = calorieTarget - Double(proteinG * 4) - Double(fatG * 9)
        switch eatingStyle {
        case .lowCarb:
            return max(50, Int(remaining * 0.6 / 4))
        case .highCarb:
            return max(0, Int(remaining * 1.1 / 4))
        default:
            return max(0, Int(remaining / 4))
        }
    }

    // MARK: - Backward-compat aliases for OnboardingTrialView (prefer AI plan when available)

    var finalTdee: Double   { Double(nutritionPlan?.calories ?? Int(calorieTarget)) }
    var finalProteinG: Int  { nutritionPlan?.proteinG ?? proteinG }
    var finalCarbsG: Int    { nutritionPlan?.carbsG ?? carbsG }
    var finalFatG: Int      { nutritionPlan?.fatG ?? fatG }

    // MARK: - Enums

    enum Goal: String, CaseIterable {
        case recomp    = "Recomp"
        case bulk      = "Bulk"
        case cut       = "Cut"
        case antiAging = "Anti-aging"

        var subtitle: String {
            switch self {
            case .recomp:    return "Build muscle & lose fat"
            case .bulk:      return "Maximize muscle gain"
            case .cut:       return "Lose fat, preserve muscle"
            case .antiAging: return "Longevity & optimization"
            }
        }
        var icon: String {
            switch self {
            case .recomp:    return "arrow.triangle.2.circlepath"
            case .bulk:      return "flame.fill"
            case .cut:       return "scissors"
            case .antiAging: return "leaf.fill"
            }
        }
    }

    enum Experience: String, CaseIterable {
        case new      = "New to it"
        case some     = "Some experience"
        case veteran  = "Veteran"

        var subtitle: String {
            switch self {
            case .new:     return "Just starting out"
            case .some:    return "1–3 years in"
            case .veteran: return "4+ years of training"
            }
        }
    }

    enum BiologicalSex: String, CaseIterable {
        case male   = "Male"
        case female = "Female"
        case other  = "Other"
    }

    enum ActivityLevel: String, CaseIterable {
        case sedentary  = "Sedentary"
        case light      = "Lightly Active"
        case moderate   = "Moderately Active"
        case active     = "Very Active"
        case veryActive = "Extremely Active"

        var multiplier: Double {
            switch self {
            case .sedentary:  return 1.2
            case .light:      return 1.375
            case .moderate:   return 1.55
            case .active:     return 1.725
            case .veryActive: return 1.9
            }
        }
        var subtitle: String {
            switch self {
            case .sedentary:  return "Desk job, no exercise"
            case .light:      return "1–3x/week"
            case .moderate:   return "3–5x/week"
            case .active:     return "6–7x/week"
            case .veryActive: return "Physical job + training"
            }
        }
    }

    enum TrainingTime: String, CaseIterable {
        case morning   = "Morning"
        case afternoon = "Afternoon"
        case evening   = "Evening"
        case varies    = "It varies"

        var icon: String {
            switch self {
            case .morning:   return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening:   return "moon.stars.fill"
            case .varies:    return "shuffle"
            }
        }
    }

    enum EatingStyle: String, CaseIterable {
        case standard            = "Standard"
        case lowCarb             = "Low Carb"
        case highCarb            = "High Carb"
        case intermittentFasting = "Intermittent Fasting"

        var subtitle: String {
            switch self {
            case .standard:            return "Balanced macros"
            case .lowCarb:             return "Under 100g carbs/day"
            case .highCarb:            return "Performance fueling"
            case .intermittentFasting: return "Time-restricted eating"
            }
        }
    }

    enum MacroMode { case auto, custom }
}

// MARK: - Flow View

struct OnboardingFlowView: View {
    @StateObject private var vm = OnboardingViewModel()
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: back chevron + progress bar
                topBar

                // Step content
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(vm.step)
                    .animation(.easeInOut(duration: 0.25), value: vm.step)
            }
        }
        .onAppear {
            Analytics.capture(.onboardingStarted)
        }
        .onChange(of: vm.step) { _, newStep in
            Analytics.capture(.onboardingStepCompleted, properties: ["step": newStep - 1, "total_steps": 12])
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                if vm.step > 1 {
                    Button {
                        withAnimation { vm.step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary)
                            .frame(width: 36, height: 36)
                    }
                } else {
                    Spacer().frame(width: 36, height: 36)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Progress bar (12 steps total, peptide goals first)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appBorder)
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.appAccent)
                        .frame(width: geo.size.width * CGFloat(vm.step - 1) / 11.0, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: vm.step)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 24)
        }
    }

    // MARK: Step routing
    //
    // Order is intentional: we ask "what do you want from peptides" first
    // because every downstream question (fitness goal, body stats, protocol)
    // is more useful once we know what the user is optimizing for.

    @ViewBuilder
    private var stepContent: some View {
        switch vm.step {
        case 1:  Step0PeptideGoalsView(vm: vm)
        case 2:  Step1GoalView(vm: vm)
        case 3:  Step2ExperienceView(vm: vm)
        case 4:  Step3SexView(vm: vm)
        case 5:  Step4AgeView(vm: vm)
        case 6:  Step5HeightView(vm: vm)
        case 7:  Step6WeightView(vm: vm)
        case 8:  Step7ActivityView(vm: vm)
        case 9:  Step8TrainingDaysView(vm: vm)
        case 10: Step9EatingStyleView(vm: vm)
        case 11: Step10ProtocolView(vm: vm)
        case 12: Step11NumbersView(vm: vm)
        default: OnboardingTrialView(vm: vm)
        }
    }
}

// MARK: - Step 0: Peptide goals (asked first so everything else is contextual)

private struct Step0PeptideGoalsView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        OnboardingGoalsView(
            selected: $vm.peptideGoals,
            onContinue: { withAnimation { vm.step += 1 } },
            onSkip: { withAnimation { vm.step += 1 } }
        )
    }
}

// MARK: - Shared UI helpers

private struct QuestionHeader: View {
    let question: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

private struct SelectionCard: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .white : Color.appTextTertiary)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : Color.appTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Color.white.opacity(0.85) : Color.appTextTertiary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(isSelected ? Color.appAccent : Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.appAccent : Color.appBorder,
                        lineWidth: isSelected ? 2 : 1.5)
        )
    }
}

private struct ContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Continue")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.appAccent)
                .cornerRadius(14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

// MARK: - Step 1: Goal (2×2 grid)

private struct Step1GoalView: View {
    @ObservedObject var vm: OnboardingViewModel

    private let goals: [OnboardingViewModel.Goal] = [.recomp, .bulk, .cut, .antiAging]

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "What's your primary goal?",
                           subtitle: "We'll tailor your plan around this.")

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(goals, id: \.self) { g in
                    Button {
                        vm.goal = g
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation { vm.step += 1 }
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: g.icon)
                                .font(.system(size: 26))
                                .foregroundColor(vm.goal == g ? .white : Color.appTextTertiary)
                            Text(g.rawValue)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(vm.goal == g ? .white : Color.appTextPrimary)
                            Text(g.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(vm.goal == g ? Color.white.opacity(0.85) : Color.appTextTertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 12)
                        .background(vm.goal == g ? Color.appAccent : Color.white)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(vm.goal == g ? Color.appAccent : Color.appBorder,
                                        lineWidth: vm.goal == g ? 2 : 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Step 2: Experience

private struct Step2ExperienceView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "How experienced are you?",
                           subtitle: "Honest answer gives better macros.")

            VStack(spacing: 12) {
                ForEach(OnboardingViewModel.Experience.allCases, id: \.self) { exp in
                    Button {
                        vm.experience = exp
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation { vm.step += 1 }
                        }
                    } label: {
                        SelectionCard(title: exp.rawValue,
                                      subtitle: exp.subtitle,
                                      isSelected: vm.experience == exp)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Step 3: Biological Sex

private struct Step3SexView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "Biological sex?",
                           subtitle: "Used for hormone-adjusted RMR.")

            VStack(spacing: 12) {
                ForEach(OnboardingViewModel.BiologicalSex.allCases, id: \.self) { sex in
                    Button {
                        vm.biologicalSex = sex
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation { vm.step += 1 }
                        }
                    } label: {
                        SelectionCard(title: sex.rawValue,
                                      isSelected: vm.biologicalSex == sex)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Step 4: Age

private struct Step4AgeView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var ageText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "How old are you?")

            Spacer()

            VStack(spacing: 4) {
                TextField("28", text: $ageText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: ageText) { _, new in
                        let filtered = String(new.filter(\.isNumber).prefix(3))
                        if filtered != new { ageText = filtered }
                    }
                    .onAppear {
                        ageText = "\(vm.age)"
                        focused = true
                    }

                Text("years")
                    .font(.system(size: 18))
                    .foregroundColor(Color.appTextTertiary)
            }

            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            ContinueButton {
                if let v = Int(ageText), v > 0 { vm.age = v }
                withAnimation { vm.step += 1 }
            }
        }
    }
}

// MARK: - Step 5: Height

private struct Step5HeightView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var valueText: String = ""
    @FocusState private var focused: Bool

    // Imperial: feet + inches stored as separate state, combined on continue
    @State private var feetText: String = ""
    @State private var inchesText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "How tall are you?")

            // Unit toggle
            Picker("Unit", selection: $vm.useImperial) {
                Text("cm").tag(false)
                Text("ft / in").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 60)
            .padding(.top, 8)
            .onChange(of: vm.useImperial) { _, _ in syncToDisplay() }

            Spacer()

            if vm.useImperial {
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(spacing: 4) {
                        TextField("5", text: $feetText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 64, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                            .focused($focused)
                            .onChange(of: feetText) { _, new in
                                feetText = String(new.filter(\.isNumber).prefix(1))
                            }
                        Text("ft").font(.system(size: 18)).foregroundColor(Color.appTextTertiary)
                    }
                    VStack(spacing: 4) {
                        TextField("10", text: $inchesText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 64, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .frame(width: 120)
                            .onChange(of: inchesText) { _, new in
                                inchesText = String(new.filter(\.isNumber).prefix(2))
                            }
                        Text("in").font(.system(size: 18)).foregroundColor(Color.appTextTertiary)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    TextField("175", text: $valueText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: valueText) { _, new in
                            valueText = String(new.filter(\.isNumber).prefix(3))
                        }
                    Text("cm").font(.system(size: 18)).foregroundColor(Color.appTextTertiary)
                }
            }

            Spacer()
        }
        .onAppear { syncToDisplay(); focused = true }
        .safeAreaInset(edge: .bottom) {
            ContinueButton {
                if vm.useImperial {
                    let ft = Double(feetText) ?? 5
                    let ins = Double(inchesText) ?? 0
                    vm.heightCm = (ft * 12 + ins) * 2.54
                } else if let v = Double(valueText), v > 0 {
                    vm.heightCm = v
                }
                withAnimation { vm.step += 1 }
            }
        }
    }

    private func syncToDisplay() {
        if vm.useImperial {
            let totalInches = vm.heightCm / 2.54
            let ft = Int(totalInches / 12)
            let ins = Int(totalInches.truncatingRemainder(dividingBy: 12))
            feetText = "\(ft)"
            inchesText = "\(ins)"
        } else {
            valueText = "\(Int(vm.heightCm))"
        }
    }
}

// MARK: - Step 6: Weight

private struct Step6WeightView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var valueText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "What do you weigh?")

            Picker("Unit", selection: $vm.useImperial) {
                Text("kg").tag(false)
                Text("lbs").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 60)
            .padding(.top, 8)
            .onChange(of: vm.useImperial) { _, _ in syncToDisplay() }

            Spacer()

            VStack(spacing: 4) {
                TextField(vm.useImperial ? "176" : "80", text: $valueText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: valueText) { _, new in
                        let filtered = String(new.filter { $0.isNumber || $0 == "." }.prefix(6))
                        if filtered != new { valueText = filtered }
                    }
                Text(vm.useImperial ? "lbs" : "kg")
                    .font(.system(size: 18))
                    .foregroundColor(Color.appTextTertiary)
            }

            Spacer()
        }
        .onAppear { syncToDisplay(); focused = true }
        .safeAreaInset(edge: .bottom) {
            ContinueButton {
                if let v = Double(valueText), v > 0 {
                    vm.weightKg = vm.useImperial ? v / 2.20462 : v
                }
                withAnimation { vm.step += 1 }
            }
        }
    }

    private func syncToDisplay() {
        if vm.useImperial {
            valueText = String(format: "%.1f", vm.weightKg * 2.20462)
        } else {
            valueText = String(format: "%.1f", vm.weightKg)
        }
    }
}

// MARK: - Step 7: Activity Level

private struct Step7ActivityView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "How active are you?",
                           subtitle: "Outside of planned workouts.")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(OnboardingViewModel.ActivityLevel.allCases, id: \.self) { lvl in
                        Button {
                            vm.activityLevel = lvl
                            Task {
                                try? await Task.sleep(for: .milliseconds(180))
                                withAnimation { vm.step += 1 }
                            }
                        } label: {
                            SelectionCard(title: lvl.rawValue,
                                          subtitle: lvl.subtitle,
                                          isSelected: vm.activityLevel == lvl)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Step 8: Training Days

private struct Step8TrainingDaysView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "Training days per week?",
                           subtitle: "Weights, cardio, or any structured session.")

            Spacer()

            HStack(spacing: 10) {
                ForEach(0...7, id: \.self) { day in
                    Button {
                        vm.trainingDaysPerWeek = day
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation { vm.step += 1 }
                        }
                    } label: {
                        let selected = vm.trainingDaysPerWeek == day
                        Text("\(day)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(selected ? Color.white : Color.appTextPrimary)
                            .frame(width: 38, height: 38)
                            .background(selected ? Color.appAccent : Color.white)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    selected ? Color.appAccent : Color.appBorder,
                                    lineWidth: selected ? 2 : 1.5
                                )
                            )
                    }
                }
            }
            .padding(.horizontal, 16)

            Text("days")
                .font(.system(size: 14))
                .foregroundColor(Color.appTextTertiary)
                .padding(.top, 10)

            Spacer()
        }
    }
}

// MARK: - Step 9: Eating Style

private struct Step9EatingStyleView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "How do you eat?",
                           subtitle: "Shapes your fat and carb targets.")

            VStack(spacing: 12) {
                ForEach(OnboardingViewModel.EatingStyle.allCases, id: \.self) { style in
                    Button {
                        vm.eatingStyle = style
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation { vm.step += 1 }
                        }
                    } label: {
                        SelectionCard(title: style.rawValue,
                                      subtitle: style.subtitle,
                                      isSelected: vm.eatingStyle == style)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Step 10: Protocol (two-phase: yes/no → compound picker)
//
// Peptide goals are now collected as Step 0, so this step only asks
// whether the user is currently on a protocol and (if yes) which compounds.

private struct Step10ProtocolView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var phase: Phase = .yesNo

    enum Phase { case yesNo, picker }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .yesNo:  yesNoView
            case .picker: compoundPicker
            }
        }
        .animation(.easeInOut(duration: 0.22), value: phase)
    }

    private var yesNoView: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "On a peptide protocol?",
                           subtitle: "We'll personalize your nutrition around your compounds.")

            VStack(spacing: 12) {
                Button {
                    vm.hasProtocol = true
                    withAnimation { phase = .picker }
                } label: {
                    SelectionCard(title: "Yes",
                                  subtitle: "I'm currently using peptides",
                                  isSelected: vm.hasProtocol == true && phase != .yesNo)
                }

                Button {
                    vm.hasProtocol = false
                    vm.selectedCompounds = []
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        withAnimation { vm.step += 1 }
                    }
                } label: {
                    SelectionCard(title: "Not yet",
                                  subtitle: "I'm curious and just getting started",
                                  isSelected: false)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var compoundPicker: some View {
        VStack(spacing: 0) {
            QuestionHeader(question: "Which compounds?",
                           subtitle: vm.peptideGoals.isEmpty
                                ? "Tap the mic and say them, or pick below."
                                : "Tap the mic, or pick from your recommendations.")

            CompoundPickerView(
                selected: $vm.selectedCompounds,
                recommendedCompounds: vm.recommendedCompounds
            )
        }
        .safeAreaInset(edge: .bottom) {
            ContinueButton {
                withAnimation { vm.step += 1 }
            }
        }
    }
}

// MARK: - Step 11: Numbers Summary (AI-powered)

private struct Step11NumbersView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoadingPlan {
                loadingView
            } else {
                planView
            }
        }
        .task {
            guard vm.nutritionPlan == nil && !vm.isLoadingPlan else { return }
            await vm.fetchNutritionPlan()
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(Color.appAccent)
                Text("Building your plan...")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text("Analyzing your goal, protocol, and training profile.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: Plan

    private var planView: some View {
        let plan = vm.nutritionPlan
        let calories    = plan?.calories    ?? Int(vm.calorieTarget)
        let proteinG    = plan?.proteinG    ?? vm.proteinG
        let carbsG      = plan?.carbsG      ?? vm.carbsG
        let fatG        = plan?.fatG        ?? vm.fatG
        let perMeal     = proteinG / max(1, vm.mealsPerDay)

        return VStack(spacing: 0) {
            QuestionHeader(question: "Your Plan",
                           subtitle: personalizationNote)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // Overall rationale (only if AI plan loaded)
                    if let rationale = plan?.overallRationale {
                        Text(rationale)
                            .font(.system(size: 14))
                            .foregroundColor(Color.appTextSecondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.hasProtocol ? Color.appAccentTint : Color(hex: "f9f4ef"))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(vm.hasProtocol ? Color.appAccent.opacity(0.25) : Color.appBorder, lineWidth: 1)
                            )
                    }

                    // Calories card
                    ExplainedNumberCard(
                        label: "Daily Calories",
                        value: "\(calories) kcal",
                        explanation: plan?.caloriesExplanation,
                        accent: true
                    )

                    // Macros
                    ExplainedNumberCard(
                        label: "Protein",
                        value: "\(proteinG) g",
                        explanation: plan?.proteinExplanation,
                        badge: vm.hasProtocol ? "Protocol-adjusted" : nil
                    )
                    ExplainedNumberCard(
                        label: "Carbs",
                        value: "\(carbsG) g",
                        explanation: plan?.carbsExplanation
                    )
                    ExplainedNumberCard(
                        label: "Fat",
                        value: "\(fatG) g",
                        explanation: plan?.fatExplanation
                    )

                    // Per-meal protein
                    NumbersCard {
                        NumbersRow(
                            label: "Protein per meal (\(vm.mealsPerDay == 5 ? "5+" : "\(vm.mealsPerDay)") meals)",
                            value: "~\(perMeal) g"
                        )
                    }

                    if let _ = vm.planLoadError {
                        Text("Using calculated targets (AI unavailable)")
                            .font(.system(size: 12))
                            .foregroundColor(Color.appTextMeta)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ContinueButton {
                withAnimation { vm.step += 1 }
            }
        }
    }

    private var personalizationNote: String {
        var parts = ["\(vm.goal.rawValue.lowercased()) goal"]
        if vm.hasProtocol { parts.append("peptide protocol") }
        parts.append("\(vm.trainingDaysPerWeek)x/week")
        return "Personalized for your " + parts.joined(separator: ", ")
    }
}

private struct ExplainedNumberCard: View {
    let label: String
    let value: String
    var explanation: String? = nil
    var accent: Bool = false
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.appTextTertiary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.appAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAccentTint)
                                .cornerRadius(6)
                        }
                    }
                    Text(value)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(accent ? Color.appAccent : Color.appTextPrimary)
                }
                Spacer()
            }

            if let explanation {
                Text(explanation)
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent ? Color.appAccent.opacity(0.3) : Color.appBorder, lineWidth: accent ? 2 : 1.5)
        )
    }
}

private struct NumbersCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.appBorder, lineWidth: 1.5))
    }
}

private struct NumbersRow: View {
    let label: String
    let value: String
    var accent: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color.appTextTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: accent ? .bold : .semibold))
                .foregroundColor(accent ? Color.appAccent : Color.appTextPrimary)
        }
    }
}
