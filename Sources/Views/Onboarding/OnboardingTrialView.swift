import RevenueCat
import RevenueCatUI
import SwiftUI
import SwiftData

struct OnboardingTrialView: View {
    @ObservedObject var vm: OnboardingViewModel
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var purchases: PurchasesManager
    @Environment(\.modelContext) private var ctx

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.appAccentTint)
                        .frame(width: 80, height: 80)
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.appAccent)
                }

                // Copy
                VStack(spacing: 8) {
                    Text("You're getting 7 days free on Pro.")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                        .multilineTextAlignment(.center)

                    Text("Full Partition Plan: meal windows, timing nudges, unlimited food history, and vial inventory.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Pro features list
                VStack(alignment: .leading, spacing: 10) {
                    ProFeatureRow(icon: "chart.bar.fill", text: "Full meal window breakdown")
                    ProFeatureRow(icon: "bell.fill", text: "Real-time timing nudges")
                    ProFeatureRow(icon: "clock.fill", text: "Unlimited food log history")
                    ProFeatureRow(icon: "drop.fill", text: "Vial inventory + reconstitution calculator")
                    ProFeatureRow(icon: "square.and.arrow.up", text: "Full history export")
                }
                .padding(16)
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
            }
            .padding(.horizontal, 24)

            Spacer()

            // CTAs
            VStack(spacing: 12) {
                Button(action: startTrial) {
                    Text("Start Free Trial")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                }

                Button(action: skipTrial) {
                    Text("Maybe later")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextTertiary)
                }

                Text("No credit card needed · Cancel anytime · $9.99/mo after trial")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { info in
                    purchases.update(info)
                    showPaywall = false
                    Task {
                        await saveProfileAndEnter()
                        authManager.completeOnboarding()
                    }
                }
                .onRestoreCompleted { info in
                    purchases.update(info)
                    showPaywall = false
                    Task {
                        await saveProfileAndEnter()
                        authManager.completeOnboarding()
                    }
                }
        }
    }

    @State private var showPaywall = false

    private func startTrial() {
        showPaywall = true
    }

    private func skipTrial() {
        Task {
            await saveProfileAndEnter()
            authManager.completeOnboarding()
        }
    }

    private func saveProfileAndEnter() async {
        guard let userId = authManager.activeUserId else { return }

        struct ProfileUpsert: Encodable {
            let user_id: String
            let weight_kg: Double
            let height_cm: Double
            let age_years: Int
            let biological_sex: String
            let activity_level: String
            let goal: String
            let experience: String
            let training_days_per_week: Int
            let eating_style: String
            let has_protocol: Bool
            let protocol_compounds: [String]
            let rmr_kcal: Double
            let tdee_kcal: Double
            let calorie_target_kcal: Double
            let macro_goal_mode: String
            let macro_goal_protein_g: Int
            let macro_goal_carbs_g: Int
            let macro_goal_fat_g: Int
        }

        let goalSlug: String
        switch vm.goal {
        case .recomp:    goalSlug = "recomp"
        case .bulk:      goalSlug = "bulk"
        case .cut:       goalSlug = "cut"
        case .antiAging: goalSlug = "anti_aging"
        }

        let eatingStyleSlug: String
        switch vm.eatingStyle {
        case .standard:            eatingStyleSlug = "standard"
        case .lowCarb:             eatingStyleSlug = "low_carb"
        case .highCarb:            eatingStyleSlug = "high_carb"
        case .intermittentFasting: eatingStyleSlug = "intermittent_fasting"
        }

        let experienceSlug: String
        switch vm.experience {
        case .new:     experienceSlug = "new"
        case .some:    experienceSlug = "some"
        case .veteran: experienceSlug = "veteran"
        }

        let payload = ProfileUpsert(
            user_id:                  userId.uuidString,
            weight_kg:                vm.weightKg,
            height_cm:                vm.heightCm,
            age_years:                vm.age,
            biological_sex:           vm.biologicalSex.rawValue.lowercased(),
            activity_level:           activityLevelSlug(vm.activityLevel),
            goal:                     goalSlug,
            experience:               experienceSlug,
            training_days_per_week:   vm.trainingDaysPerWeek,
            eating_style:             eatingStyleSlug,
            has_protocol:             vm.hasProtocol,
            protocol_compounds:       Array(vm.selectedCompounds).sorted(),
            rmr_kcal:                 vm.rmr,
            tdee_kcal:                vm.tdee,
            calorie_target_kcal:      Double(vm.finalTdee),
            macro_goal_mode:          "auto",
            macro_goal_protein_g:     vm.finalProteinG,
            macro_goal_carbs_g:       vm.finalCarbsG,
            macro_goal_fat_g:         vm.finalFatG
        )

        await Task.detached {
            do {
                try await supabase
                    .from("users_profiles")
                    .upsert(payload, onConflict: "user_id")
                    .execute()
            } catch {
                // non-blocking — user can update in Settings
            }
        }.value

        // Cache locally for Partition Plan and Today view
        let existing = try? ctx.fetch(FetchDescriptor<CachedUserProfile>())
        existing?.forEach { ctx.delete($0) }
        let cached = CachedUserProfile(
            userId:                userId.uuidString,
            weightKg:              vm.weightKg,
            heightCm:              vm.heightCm,
            ageYears:              vm.age,
            biologicalSex:         vm.biologicalSex.rawValue.lowercased(),
            activityLevel:         activityLevelSlug(vm.activityLevel),
            goal:                  goalSlug,
            experience:            experienceSlug,
            trainingDaysPerWeek:   vm.trainingDaysPerWeek,
            eatingStyle:           eatingStyleSlug,
            hasProtocol:           vm.hasProtocol,
            protocolCompounds:     Array(vm.selectedCompounds).sorted(),
            rmrKcal:               vm.rmr,
            tdeeKcal:              vm.tdee,
            calorieTargetKcal:     Double(vm.finalTdee),
            proteinG:              vm.finalProteinG,
            carbsG:                vm.finalCarbsG,
            fatG:                  vm.finalFatG
        )
        ctx.insert(cached)
        try? ctx.save()

        // Create LocalProtocol from onboarding compounds so Protocol tab + injection
        // site quick-log work immediately without requiring manual setup.
        if vm.hasProtocol && !vm.selectedCompounds.isEmpty {
            let existingCount = (try? ctx.fetchCount(FetchDescriptor<LocalProtocol>())) ?? 0
            if existingCount == 0 {
                let proto = LocalProtocol(userId: userId.uuidString, name: "My Protocol")
                ctx.insert(proto)
                for name in vm.selectedCompounds.sorted() {
                    let comp = LocalProtocolCompound(
                        protocolId:   proto.id,
                        compoundName: name,
                        doseMcg:      defaultDoseMcg(for: name),
                        frequency:    defaultFrequency(for: name),
                        doseTimes:    ["08:00"]
                    )
                    ctx.insert(comp)
                    proto.compounds.append(comp)
                }
                try? ctx.save()
                await SyncService.shared.pushProtocol(proto, userId: userId.uuidString)
            }
        }

        _ = await NotificationScheduler.requestPermission()
    }

    // Sensible defaults so the protocol is usable immediately.
    // User can edit exact doses in the Protocol tab.
    private func defaultDoseMcg(for compound: String) -> Double {
        let table: [String: Double] = [
            "BPC-157": 500, "TB-500": 2500, "CJC-1295": 300, "Ipamorelin": 200,
            "GHRP-2": 200, "GHRP-6": 200, "Sermorelin": 300, "Tesamorelin": 1000,
            "AOD-9604": 300, "Semaglutide": 250, "Tirzepatide": 2500,
            "PT-141": 1000, "Melanotan II": 1000, "Thymosin Alpha-1": 1600,
            "GHK-Cu": 2000, "MK-677": 25000, "Hexarelin": 200,
            "Selank": 300, "Semax": 300,
        ]
        return table[compound] ?? 500
    }

    private func defaultFrequency(for compound: String) -> String {
        let weekly:  Set<String> = ["Semaglutide", "Tirzepatide"]
        let eod:     Set<String> = ["TB-500", "Thymosin Alpha-1", "Melanotan II"]
        if weekly.contains(compound) { return "weekly" }
        if eod.contains(compound)    { return "eod" }
        return "daily"
    }

    private func activityLevelSlug(_ level: OnboardingViewModel.ActivityLevel) -> String {
        switch level {
        case .sedentary:  return "sedentary"
        case .light:      return "light"
        case .moderate:   return "moderate"
        case .active:     return "active"
        case .veryActive: return "very_active"
        }
    }
}

struct ProFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color.appAccent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color.appTextSecondary)
        }
    }
}
