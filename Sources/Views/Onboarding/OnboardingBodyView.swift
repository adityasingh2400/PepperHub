import SwiftUI

struct OnboardingBodyView: View {
    @ObservedObject var vm: OnboardingViewModel

    @State private var weightText  = ""
    @State private var heightFtText = ""
    @State private var heightInText = ""
    @State private var heightCmText = ""
    @State private var ageText     = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Body")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(Color.appTextPrimary)
                Text("We'll calculate your calorie and macro targets.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextTertiary)
            }

            // Weight row
            OnboardingSection(title: "Weight") {
                HStack(spacing: 8) {
                    PTextField(
                        placeholder: vm.useImperial ? "lbs" : "kg",
                        text: $weightText,
                        keyboardType: .decimalPad
                    )
                    .onChange(of: weightText) { _, val in
                        if let d = Double(val) {
                            vm.weightKg = vm.useImperial ? d / 2.20462 : d
                        }
                    }
                    UnitToggle(leftLabel: "kg", rightLabel: "lbs", isRight: $vm.useImperial)
                }
            }

            // Height + Age in one row
            HStack(spacing: 12) {
                OnboardingSection(title: "Height") {
                    if vm.useImperial {
                        HStack(spacing: 4) {
                            PTextField(placeholder: "ft", text: $heightFtText, keyboardType: .numberPad)
                                .onChange(of: heightFtText) { _, _ in syncHeight() }
                            PTextField(placeholder: "in", text: $heightInText, keyboardType: .decimalPad)
                                .onChange(of: heightInText) { _, _ in syncHeight() }
                        }
                    } else {
                        PTextField(placeholder: "cm", text: $heightCmText, keyboardType: .decimalPad)
                            .onChange(of: heightCmText) { _, val in
                                if let d = Double(val) { vm.heightCm = d }
                            }
                    }
                }

                OnboardingSection(title: "Age") {
                    PTextField(placeholder: "yrs", text: $ageText, keyboardType: .numberPad)
                        .onChange(of: ageText) { _, val in
                            if let i = Int(val) { vm.age = i }
                        }
                }
                .frame(maxWidth: 100)
            }

            // Biological Sex
            OnboardingSection(title: "Biological Sex") {
                HStack(spacing: 8) {
                    ForEach(OnboardingViewModel.BiologicalSex.allCases, id: \.self) { sex in
                        PillButton(label: sex.rawValue, selected: vm.biologicalSex == sex) {
                            vm.biologicalSex = sex
                        }
                    }
                }
            }

            // Activity Level — menu picker (collapses 5 rows into one line)
            OnboardingSection(title: "Activity Level") {
                Menu {
                    ForEach(OnboardingViewModel.ActivityLevel.allCases, id: \.self) { level in
                        Button(action: { vm.activityLevel = level }) {
                            HStack {
                                Text(level.rawValue)
                                if vm.activityLevel == level {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.activityLevel.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary)
                            Text(vm.activityLevel.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(Color.appTextTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(Color.appAccent)
                    }
                    .padding(14)
                    .background(Color.appCard)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1.5))
                }
            }

            // Goal
            OnboardingSection(title: "Goal") {
                HStack(spacing: 8) {
                    ForEach(OnboardingViewModel.Goal.allCases, id: \.self) { goal in
                        GoalCard(
                            title: goal.rawValue,
                            subtitle: goal.subtitle,
                            selected: vm.goal == goal
                        ) { vm.goal = goal }
                    }
                }
            }

            Spacer()

            // CTA
            VStack(spacing: 10) {
                Button(action: { vm.step = 2 }) {
                    Text("Continue →")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                }
                Button("Skip for now") { vm.step = 3 }
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .onAppear { populateFromVm() }
    }

    private func syncHeight() {
        let ft = Double(heightFtText) ?? 0
        let inches = Double(heightInText) ?? 0
        vm.heightCm = ((ft * 12) + inches) * 2.54
    }

    private func populateFromVm() {
        if vm.useImperial {
            let lbs = vm.weightKg * 2.20462
            weightText = lbs == 176.37 ? "" : String(format: "%.0f", lbs)
            let totalIn = vm.heightCm / 2.54
            let ft = Int(totalIn / 12)
            let ins = totalIn.truncatingRemainder(dividingBy: 12)
            heightFtText = ft == 5 ? "" : "\(ft)"
            heightInText = ins == 10.83 ? "" : String(format: "%.0f", ins)
        } else {
            weightText  = vm.weightKg == 80 ? "" : String(format: "%.0f", vm.weightKg)
            heightCmText = vm.heightCm == 175 ? "" : String(format: "%.0f", vm.heightCm)
        }
        ageText = vm.age == 28 ? "" : "\(vm.age)"
    }
}

// MARK: - Sub-components

struct OnboardingSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)
            content
        }
    }
}

struct UnitToggle: View {
    let leftLabel: String
    let rightLabel: String
    @Binding var isRight: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleOption(leftLabel, selected: !isRight) { isRight = false }
            toggleOption(rightLabel, selected: isRight) { isRight = true }
        }
        .background(Color.appBorder)
        .cornerRadius(8)
    }

    private func toggleOption(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? Color.appAccent : Color.appTextTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.white : Color.clear)
                .cornerRadius(7)
        }
    }
}

struct PillButton: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? .white : Color.appTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selected ? Color.appAccent : Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
                )
        }
    }
}

struct ActivityRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? .white : Color.appTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(selected ? Color.white.opacity(0.85) : Color.appTextTertiary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                } else {
                    Circle()
                        .strokeBorder(Color.appBorder, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(14)
            .background(selected ? Color.appAccent : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
            )
        }
    }
}

struct GoalCard: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(selected ? .white : Color.appTextPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(selected ? Color.white.opacity(0.85) : Color.appTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(selected ? Color.appAccent : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
            )
        }
    }
}
