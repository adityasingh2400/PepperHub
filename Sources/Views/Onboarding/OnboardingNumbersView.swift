import SwiftUI

// Legacy view — kept for potential direct reference from other parts of the app.
// The new onboarding flow uses Step13NumbersView inside OnboardingFlowView.swift.
struct OnboardingNumbersView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Numbers")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text("Based on what you told us.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextTertiary)
                }

                MetabolismCard(vm: vm)
                MacroTargetsCard(vm: vm)
            }
            .padding(20)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: { vm.step += 1 }) {
                    Text("These look right →")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(Color.appBackground)
        }
    }
}

// MARK: - Metabolism Card

private struct MetabolismCard: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RMR")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.0)
                    Text("\(Int(vm.rmr).formatted()) kcal/day")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text("calories your body burns at rest")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
            }
            .padding(16)

            Divider().background(Color.appBorder)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TDEE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.0)
                    Text("\(Int(vm.finalTdee).formatted()) kcal/day")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text("total daily energy expenditure")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
            }
            .padding(16)

            Divider().background(Color.appBorder)

            HStack {
                Text("Goal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
                Text(vm.goal.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.appAccent)
            }
            .padding(16)
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Macro Targets Card

private struct MacroTargetsCard: View {
    @ObservedObject var vm: OnboardingViewModel

    private var totalKcal: Int { vm.finalProteinG * 4 + vm.finalCarbsG * 4 + vm.finalFatG * 9 }

    var body: some View {
        VStack(spacing: 0) {
            Text("DAILY MACRO TARGETS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

            Divider().background(Color.appBorder)

            MacroRow(name: "Protein", grams: vm.finalProteinG,
                     totalKcal: Int(vm.finalTdee), color: Color(hex: "60a5fa"))
                .padding(.horizontal, 16).padding(.vertical, 10)
            MacroRow(name: "Carbs", grams: vm.finalCarbsG,
                     totalKcal: Int(vm.finalTdee), color: Color(hex: "fbbf24"))
                .padding(.horizontal, 16).padding(.vertical, 10)
            MacroRow(name: "Fat", grams: vm.finalFatG,
                     totalKcal: Int(vm.finalTdee), color: Color(hex: "f472b6"))
                .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().background(Color.appBorder)

            HStack {
                Text("Total")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
                Text("\(totalKcal) kcal")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
            }
            .padding(16)
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Reusable components

struct MacroRow: View {
    let name: String
    let grams: Int
    let totalKcal: Int
    let color: Color

    private var pct: Int {
        let kcal: Int
        switch name {
        case "Fat": kcal = grams * 9
        default:    kcal = grams * 4
        }
        guard totalKcal > 0 else { return 0 }
        return Int(Double(kcal) / Double(totalKcal) * 100)
    }

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextSecondary)
                .frame(width: 60, alignment: .leading)
            Text("\(grams)g")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
                .frame(width: 48)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appDivider).frame(height: 6)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(pct) / 100, height: 6)
                }
                .frame(height: 6)
                .padding(.top, 5)
            }
            .frame(height: 16)
            Text("(\(pct)%)")
                .font(.system(size: 12))
                .foregroundColor(Color.appTextMeta)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct MacroStepper: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextSecondary)
            Spacer()
            HStack(spacing: 12) {
                Button(action: { onChange(max(0, value - 5)) }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Color.appAccent)
                }
                Text("\(value)g")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                    .frame(width: 48, alignment: .center)
                Button(action: { onChange(value + 5) }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Color.appAccent)
                }
            }
        }
    }
}
