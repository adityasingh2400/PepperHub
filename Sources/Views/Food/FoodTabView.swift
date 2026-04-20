import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

// MARK: - Meal Window

enum FoodMeal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snacks"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "bag.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .breakfast: return "f59e0b"
        case .lunch:     return "10b981"
        case .dinner:    return "6366f1"
        case .snack:     return "0ea5e9"
        }
    }

    static var current: FoodMeal {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snack
        }
    }
}

// MARK: - Main Food Tab

struct FoodTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx

    @State private var tab: FoodTabSection = .log
    @State private var showScanner = false
    @State private var showFoodDetail: FoodItem? = nil
    @State private var showManualEntry = false
    @State private var scanError: String? = nil

    enum FoodTabSection: String, CaseIterable {
        case log = "Log"
        case scan = "Scan"
        case photo = "Photo"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom segmented control
                HStack(spacing: 6) {
                    ForEach(FoodTabSection.allCases, id: \.self) { section in
                        Button(action: { tab = section }) {
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(tab == section ? Color.appAccent : Color.appTextMeta)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(tab == section ? Color.appAccentTint : Color.clear)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appBackground)

                Divider().overlay(Color.appBorder)

                switch tab {
                case .log:  FoodLogView()
                case .scan: ScanTabView(
                    showScanner: $showScanner,
                    onItemFound: { item in showFoodDetail = item },
                    onManualEntry: { showManualEntry = true }
                )
                case .photo: PhotoMealEstimationView()
                    .environmentObject(authManager)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showScanner) {
                BarcodeScanSheet { barcode in
                    showScanner = false
                    Analytics.capture(.barcodeScanStarted)
                    Task {
                        let svc = OpenFoodFactsService(modelContext: ctx)
                        do {
                            if let item = try await svc.lookup(barcode: barcode) {
                                Analytics.capture(.barcodeScanSuccess)
                                showFoodDetail = item
                            } else {
                                Analytics.capture(.barcodeScanFailed, properties: ["reason": "not_found"])
                                scanError = "Product not found in database."
                                showManualEntry = true
                            }
                        } catch {
                            Analytics.capture(.barcodeScanFailed, properties: ["reason": "network_error"])
                            scanError = "Couldn't reach Open Food Facts."
                            showManualEntry = true
                        }
                    }
                }
            }
            .sheet(item: $showFoodDetail) { item in
                FoodConfirmSheet(item: item, meal: FoodMeal.current)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showManualEntry, onDismiss: { scanError = nil }) {
                ManualFoodEntrySheet(prefillName: "", scanErrorMessage: scanError)
                    .environmentObject(authManager)
            }
        }
    }
}

// MARK: - Scan Tab

struct ScanTabView: View {
    @Binding var showScanner: Bool
    let onItemFound: (FoodItem) -> Void
    let onManualEntry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(Color.appBorder)

            VStack(spacing: 8) {
                Text("Scan a Barcode")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                Text("Point your camera at any food barcode to instantly get macros.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
                Text("Powered by Open Food Facts")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
            }
            .padding(.horizontal, 32)

            Button(action: { showScanner = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("Open Scanner")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.appAccent)
                .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .disabled(!DataScannerViewController.isSupported)

            if !DataScannerViewController.isSupported {
                Text("Barcode scanning not supported on this device.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button("Enter manually instead") {
                onManualEntry()
            }
            .font(.system(size: 14))
            .foregroundColor(Color.appTextTertiary)

            Spacer()
        }
    }
}

// MARK: - VisionKit Scanner Sheet

struct BarcodeScanSheet: View {
    let onBarcode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BarcodeScannerRepresentable { barcode in
                onBarcode(barcode)
            }
            .ignoresSafeArea()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
            }
            .padding(20)
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    @MainActor
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        private var scanned = false

        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        nonisolated func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            let payloads: [String] = items.compactMap {
                if case .barcode(let b) = $0 { return b.payloadStringValue }
                return nil
            }
            Task { @MainActor in
                guard !self.scanned, let payload = payloads.first else { return }
                self.scanned = true
                self.onBarcode(payload)
            }
        }
    }
}

// MARK: - Food Confirm Sheet

struct FoodConfirmSheet: View {
    let item: FoodItem
    var meal: FoodMeal = .snack
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOptionIdx: Int = 0
    @State private var qty: Int = 1

    init(item: FoodItem, meal: FoodMeal = .snack) {
        self.item = item
        self.meal = meal
    }

    var options: [(label: String, grams: Double)] {
        if !item.servingOptions.isEmpty {
            return item.servingOptions.map { ($0.label, $0.grams) }
        }
        let unit = item.servingUnit.isEmpty ? "g" : item.servingUnit
        return [("\(Int(item.servingQty)) \(unit)", item.servingQty)]
    }

    var selectedGrams: Double {
        options[min(selectedOptionIdx, options.count - 1)].grams * Double(qty)
    }

    var scaledKcal:    Int    { Int(item.kcalPer100g    * selectedGrams / 100) }
    var scaledProtein: Double { item.proteinPer100g * selectedGrams / 100 }
    var scaledCarbs:   Double { item.carbsPer100g   * selectedGrams / 100 }
    var scaledFat:     Double { item.fatPer100g     * selectedGrams / 100 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Food name
                    Text(item.name)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Color.appTextPrimary)

                    // Serving type pills
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SERVING SIZE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(options.indices, id: \.self) { i in
                                    let opt = options[i]
                                    Button(action: { selectedOptionIdx = i }) {
                                        VStack(spacing: 2) {
                                            Text(opt.label)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("\(Int(opt.grams))g")
                                                .font(.system(size: 10))
                                                .opacity(0.7)
                                        }
                                        .foregroundColor(selectedOptionIdx == i ? .white : Color.appTextSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedOptionIdx == i ? Color.appAccent : Color.white)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedOptionIdx == i ? Color.clear : Color.appBorder, lineWidth: 1))
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    // Quantity stepper
                    VStack(alignment: .leading, spacing: 10) {
                        Text("QUANTITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)

                        HStack(spacing: 16) {
                            Button(action: { if qty > 1 { qty -= 1 } }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(qty > 1 ? Color.appAccent : Color(hex: "d1d5db"))
                            }
                            VStack(spacing: 2) {
                                Text("\(qty)")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundColor(Color.appTextPrimary)
                                    .frame(minWidth: 32)
                                Text("\(Int(selectedGrams))g total")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.appTextMeta)
                            }
                            Button(action: { qty += 1 }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color.appAccent)
                            }
                        }
                    }

                    // Macros
                    VStack(spacing: 0) {
                        MacroDetailRow(label: "Calories", value: "\(scaledKcal) kcal", accent: true)
                        Divider()
                        MacroDetailRow(label: "Protein", value: "\(String(format: "%.1f", scaledProtein))g")
                        Divider()
                        MacroDetailRow(label: "Carbs",   value: "\(String(format: "%.1f", scaledCarbs))g")
                        Divider()
                        MacroDetailRow(label: "Fat",     value: "\(String(format: "%.1f", scaledFat))g")
                    }
                    .background(Color.appCard)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add to \(meal.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { save() }.fontWeight(.bold) }
            }
        }
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        let opt = options[min(selectedOptionIdx, options.count - 1)]
        let entry = LocalFoodLog(
            userId: userId,
            foodName: item.name,
            kcal: scaledKcal,
            proteinG: scaledProtein,
            carbsG: scaledCarbs,
            fatG: scaledFat,
            source: item.barcode.hasPrefix("usda:") ? "search" : item.barcode.isEmpty ? "manual" : "barcode",
            mealWindow: meal.rawValue,
            barcode: item.barcode.isEmpty || item.barcode.hasPrefix("usda:") ? nil : item.barcode
        )
        entry.servingQty = selectedGrams
        entry.servingUnit = opt.label
        entry.fiberG  = item.fiberPer100g.map  { $0 * selectedGrams / 100 }
        entry.sugarG  = item.sugarPer100g.map  { $0 * selectedGrams / 100 }
        entry.satFatG = item.satFatPer100g.map { $0 * selectedGrams / 100 }
        entry.sodiumMg = item.sodiumPer100g.map { $0 * 1000 * selectedGrams / 100 }
        ctx.insert(entry)
        try? ctx.save()
        Task { await SyncService.shared.pushFoodLog(entry, context: ctx) }
        dismiss()
    }
}

struct MacroDetailRow: View {
    let label: String
    let value: String
    var accent = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: accent ? .bold : .regular))
                .foregroundColor(accent ? Color.appTextPrimary : Color.appTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent ? Color.appAccent : Color.appTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Food Log View

struct FoodLogView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var purchases: PurchasesManager

    @Query(sort: \LocalFoodLog.loggedAt, order: .reverse)
    private var allLogs: [LocalFoodLog]

    @Query private var profileCache: [CachedUserProfile]

    @State private var searchMeal: FoodMeal? = nil
    @State private var selectedDate = Date()
    @State private var showPaywall = false

    private var historyLimit: Date {
        Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    }

    var profile: CachedUserProfile? { profileCache.first }

    var todayLogs: [LocalFoodLog] {
        allLogs.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
    }

    var todayTotals: (kcal: Int, protein: Double, carbs: Double, fat: Double) {
        todayLogs.reduce((0, 0, 0, 0)) { acc, log in
            (acc.0 + log.kcal, acc.1 + log.proteinG, acc.2 + log.carbsG, acc.3 + log.fatG)
        }
    }

    func logs(for meal: FoodMeal) -> [LocalFoodLog] {
        todayLogs.filter { $0.mealWindow == meal.rawValue }
    }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    Button(action: {
                        let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                        if !purchases.isPro && prev < historyLimit {
                            showPaywall = true
                        } else {
                            selectedDate = prev
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.appAccent)
                    }
                    Spacer()
                    Text(dateLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Spacer()
                    Button(action: {
                        let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                        if !Calendar.current.isDateInToday(next) && next > Date() { return }
                        selectedDate = next
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Calendar.current.isDateInToday(selectedDate) ? Color(hex: "d1d5db") : Color.appAccent)
                    }
                    .disabled(Calendar.current.isDateInToday(selectedDate))
                }
                .padding(.horizontal, 4)

                TodayMacroSummaryCard(
                    kcal: todayTotals.kcal,
                    protein: todayTotals.protein,
                    carbs: todayTotals.carbs,
                    fat: todayTotals.fat,
                    targetKcal: profile.map { Int($0.calorieTargetKcal > 0 ? $0.calorieTargetKcal : $0.tdeeKcal) },
                    targetProtein: profile?.macroGoalProteinG,
                    targetCarbs: profile?.macroGoalCarbsG,
                    targetFat: profile?.macroGoalFatG
                )

                if purchases.isPro {
                    MacroTrendCard(
                        logs: allLogs,
                        targetKcal: profile.map { Int($0.calorieTargetKcal > 0 ? $0.calorieTargetKcal : $0.tdeeKcal) },
                        targetProtein: profile?.macroGoalProteinG
                    )
                } else {
                    LockedChartCard(
                        title: "7-DAY MACRO TREND",
                        detail: "See how your calories and macros trend week over week.",
                        onUnlock: { showPaywall = true }
                    )
                }

                ForEach(FoodMeal.allCases) { meal in
                    MealSectionCard(meal: meal, logs: logs(for: meal)) {
                        searchMeal = meal
                    }
                }

                if !purchases.isPro {
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                            Text("Pro unlocks full history · Free shows 14 days")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appAccentTint)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(16)
        }
        .sheet(item: $searchMeal) { meal in
            FoodSearchSheet(meal: meal)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
    }
}

// MARK: - Meal Section Card

struct MealSectionCard: View {
    let meal: FoodMeal
    let logs: [LocalFoodLog]
    let onAdd: () -> Void
    @Environment(\.modelContext) private var ctx

    var mealKcal: Int { logs.reduce(0) { $0 + $1.kcal } }
    var mealProtein: Double { logs.reduce(0) { $0 + $1.proteinG } }
    var mealCarbs:   Double { logs.reduce(0) { $0 + $1.carbsG } }
    var mealFat:     Double { logs.reduce(0) { $0 + $1.fatG } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: meal.colorHex).opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: meal.icon)
                            .font(.system(size: 17))
                            .foregroundColor(Color(hex: meal.colorHex))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    if mealKcal > 0 {
                        Text("\(mealKcal) kcal · \(String(format: "%.0f", mealProtein))P \(String(format: "%.0f", mealCarbs))C \(String(format: "%.0f", mealFat))F")
                            .font(.system(size: 11))
                            .foregroundColor(Color.appTextMeta)
                    } else {
                        Text("Nothing logged")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "c4b5a0"))
                    }
                }
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: meal.colorHex))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !logs.isEmpty {
                Divider().overlay(Color.appDivider)
                ForEach(logs) { log in
                    MealItemRow(log: log)
                    if log.id != logs.last?.id {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct MealItemRow: View {
    @Environment(\.modelContext) private var ctx
    let log: LocalFoodLog

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(log.foodName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.appTextPrimary)
                    .lineLimit(1)
                Text("\(String(format: "%.0f", log.proteinG))P · \(String(format: "%.0f", log.carbsG))C · \(String(format: "%.0f", log.fatG))F")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appTextMeta)
            }
            Spacer()
            Text("\(log.kcal) kcal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ctx.delete(log)
                try? ctx.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct TodayMacroSummaryCard: View {
    let kcal: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    var targetKcal: Int?
    var targetProtein: Int?
    var targetCarbs: Int?
    var targetFat: Int?

    var calPct: Double {
        guard let t = targetKcal, t > 0 else { return -1 }
        return min(1, Double(kcal) / Double(t))
    }

    var body: some View {
        VStack(spacing: 14) {
            // Calorie row
            HStack {
                Text("Calories")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
                if let t = targetKcal {
                    Text("\(kcal) / \(t) kcal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(kcal > t ? Color(hex: "dc2626") : Color.appTextPrimary)
                } else {
                    Text("\(kcal) kcal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                }
            }
            if calPct >= 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appDivider).frame(height: 6)
                        Capsule()
                            .fill(calPct > 1 ? Color(hex: "dc2626") : Color.appAccent)
                            .frame(width: geo.size.width * CGFloat(min(1, calPct)), height: 6)
                    }
                }.frame(height: 6)
            }

            Divider().overlay(Color.appDivider)

            // Macro chips
            HStack(spacing: 0) {
                MacroProgressChip(
                    value: Int(protein), target: targetProtein,
                    label: "Protein", color: Color(hex: "1d4ed8")
                )
                Divider().frame(width: 1, height: 36).overlay(Color.appDivider)
                MacroProgressChip(
                    value: Int(carbs), target: targetCarbs,
                    label: "Carbs", color: Color(hex: "b45309")
                )
                Divider().frame(width: 1, height: 36).overlay(Color.appDivider)
                MacroProgressChip(
                    value: Int(fat), target: targetFat,
                    label: "Fat", color: Color(hex: "9d174d")
                )
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct MacroProgressChip: View {
    let value: Int
    let target: Int?
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            if let t = target {
                Text("\(value)/\(t)g")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(value > t ? Color(hex: "dc2626") : color)
            } else {
                Text("\(value)g")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Food Search Sheet

struct FoodSearchSheet: View {
    var meal: FoodMeal = .snack
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var selectedItem: FoodItem? = nil
    @State private var showManual = false
    @FocusState private var focused: Bool

    @Query(sort: \LocalFoodLog.loggedAt, order: .reverse)
    private var recentLogs: [LocalFoodLog]

    private var recentUnique: [LocalFoodLog] {
        var seen = Set<String>()
        return recentLogs.filter { seen.insert($0.foodName).inserted }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(isSearching ? Color.appAccent : Color.appTextMeta)
                    TextField("Search food...", text: $query)
                        .font(.system(size: 15))
                        .focused($focused)
                        .submitLabel(.search)
                        .onChange(of: query) { _, newVal in
                            scheduleSearch(newVal)
                        }
                    if !query.isEmpty {
                        Button(action: {
                            query = ""
                            results = []
                            searchTask?.cancel()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.appTextMeta)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.appCard)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)

                Divider().overlay(Color.appBorder)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if query.isEmpty {
                            // Recent foods
                            if !recentUnique.isEmpty {
                                sectionHeader("RECENT")
                                ForEach(recentUnique) { log in
                                    recentRow(log)
                                    Divider().padding(.leading, 50)
                                }
                            }

                            // Manual entry
                            addManualRow()

                        } else if isSearching {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(Color.appAccent)
                                Text("Searching...")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.appTextTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)

                        } else if !results.isEmpty {
                            sectionHeader("RESULTS")
                            ForEach(results) { item in
                                resultRow(item)
                                if item.id != results.last?.id {
                                    Divider().padding(.leading, 50)
                                }
                            }
                            addManualRow()

                        } else if !query.isEmpty {
                            VStack(spacing: 8) {
                                Text("No results for \"\(query)\"")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary)
                                Text("Try a different spelling, or add it manually.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.appTextTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .padding(.horizontal, 32)

                            addManualRow()
                        }
                    }
                    .padding(.bottom, 16)
                }
                .background(Color.appBackground)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add to \(meal.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                FoodConfirmSheet(item: item, meal: meal)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showManual) {
                ManualFoodEntrySheet(prefillName: query)
                    .environmentObject(authManager)
            }
        }
        .onAppear { focused = true }
    }

    // MARK: - Row builders

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color.appTextMeta)
            .kerning(1.2)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func resultRow(_ item: FoodItem) -> some View {
        Button(action: { selectedItem = item }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appAccentTint)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: 14))
                            .foregroundColor(Color.appAccent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary)
                        .lineLimit(2)
                    Text("\(Int(item.kcalPer100g)) kcal · \(String(format: "%.0f", item.proteinPer100g))P · \(String(format: "%.0f", item.carbsPer100g))C · \(String(format: "%.0f", item.fatPer100g))F per 100g")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.appAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
    }

    @ViewBuilder
    private func recentRow(_ log: LocalFoodLog) -> some View {
        Button(action: {
            // Reconstruct as per-100g so the confirm sheet shows the right macros at serving=100g
            let item = FoodItem(
                barcode: log.barcode ?? "",
                name: log.foodName,
                kcalPer100g: Double(log.kcal),
                proteinPer100g: log.proteinG,
                carbsPer100g: log.carbsG,
                fatPer100g: log.fatG,
                fiberPer100g: nil, sugarPer100g: nil, satFatPer100g: nil, sodiumPer100g: nil,
                servingQty: 100,
                servingUnit: "g"
            )
            selectedItem = item
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appDivider)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(Color.appTextMeta)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.foodName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary)
                        .lineLimit(1)
                    Text("\(log.kcal) kcal · \(String(format: "%.0fP", log.proteinG)) · \(String(format: "%.0fC", log.carbsG)) · \(String(format: "%.0fF", log.fatG))")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.appAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
    }

    @ViewBuilder
    private func addManualRow() -> some View {
        Button(action: { showManual = true }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appDivider)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(Color.appTextTertiary)
                    )
                Text("Add manually")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
        .padding(.top, 12)
    }

    // MARK: - Search logic

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }
            let svc = OpenFoodFactsService(modelContext: ctx)
            if let items = try? await svc.search(query: text), !Task.isCancelled {
                results = items
                isSearching = false
            } else if !Task.isCancelled {
                results = []
                isSearching = false
            }
        }
    }
}

// MARK: - Manual Entry Sheet

struct ManualFoodEntrySheet: View {
    let prefillName: String
    var scanErrorMessage: String? = nil
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var meal: FoodMeal = FoodMeal.current
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""

    init(prefillName: String, scanErrorMessage: String? = nil) {
        self.prefillName = prefillName
        self.scanErrorMessage = scanErrorMessage
        self._name = State(initialValue: prefillName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    if let errorMsg = scanErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 14))
                            Text(errorMsg + " Enter details manually.")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(Color(hex: "92400e"))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "fef3c7"))
                        .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOOD NAME")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        TextField("e.g. Chicken breast", text: $name)
                            .font(.system(size: 15))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEAL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        HStack(spacing: 8) {
                            ForEach(FoodMeal.allCases) { m in
                                Button(action: { meal = m }) {
                                    Text(m.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(meal == m ? .white : Color.appTextSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(meal == m ? Color(hex: meal.colorHex) : Color.white)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(meal == m ? Color.clear : Color.appBorder, lineWidth: 1))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("MACROS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            macroRow(label: "Calories", placeholder: "kcal", text: $kcalText, keyboard: .numberPad)
                            Divider().overlay(Color.appDivider)
                            macroRow(label: "Protein", placeholder: "g", text: $proteinText, keyboard: .decimalPad)
                            Divider().overlay(Color.appDivider)
                            macroRow(label: "Carbs", placeholder: "g", text: $carbsText, keyboard: .decimalPad)
                            Divider().overlay(Color.appDivider)
                            macroRow(label: "Fat", placeholder: "g", text: $fatText, keyboard: .decimalPad)
                        }
                        .background(Color.appCard)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
                    }

                    Button(action: save) {
                        Text("Add Food")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(name.isEmpty || kcalText.isEmpty ? Color(hex: "d1d5db") : Color.appAccent)
                            .cornerRadius(14)
                    }
                    .disabled(name.isEmpty || kcalText.isEmpty)
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func macroRow(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color.appTextSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary)
                .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        let entry = LocalFoodLog(
            userId: userId,
            foodName: name,
            kcal: Int(kcalText) ?? 0,
            proteinG: Double(proteinText) ?? 0,
            carbsG: Double(carbsText) ?? 0,
            fatG: Double(fatText) ?? 0,
            source: "manual",
            mealWindow: meal.rawValue
        )
        ctx.insert(entry)
        try? ctx.save()
        Analytics.capture(.foodLogged, properties: ["source": "manual", "meal": meal.rawValue, "kcal": entry.kcal])
        Task { await SyncService.shared.pushFoodLog(entry, context: ctx) }
        dismiss()
    }
}

// MARK: - Photo Meal Estimation (v1.1)

struct PhotoMealEstimationView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var estimatedMeals: [PhotoMealEstimate] = []
    @State private var errorMessage: String?
    @State private var showConfirmSheet: PhotoMealEstimate?
    @State private var selectedMeal = FoodMeal.current

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundColor(Color.appAccent)
                    Text("Photo Meal Estimation")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("Take or pick a photo of your meal and AI will estimate the macros.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    Button(action: { showCamera = true }) {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.appAccent)
                            .cornerRadius(12)
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.appAccentTint)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)

                if selectedImage != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.appTextTertiary)
                        HStack(spacing: 8) {
                            ForEach(FoodMeal.allCases) { meal in
                                Button(action: { selectedMeal = meal }) {
                                    Text(meal.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedMeal == meal ? Color.appAccent : Color.appTextSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(selectedMeal == meal ? Color.appAccentTint : Color.appCard)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                            selectedMeal == meal ? Color.appAccent.opacity(0.4) : Color.appBorder,
                                            lineWidth: 1
                                        ))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Button(action: analyzePhoto) {
                        Group {
                            if isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Analyzing...")
                                }
                            } else {
                                Label("Estimate Macros", systemImage: "sparkles")
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                    }
                    .disabled(isAnalyzing)
                    .padding(.horizontal, 16)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                }

                if !estimatedMeals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detected Items")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.appTextPrimary)
                            .padding(.horizontal, 16)
                        ForEach(estimatedMeals) { item in
                            PhotoMealEstimateCard(estimate: item) { showConfirmSheet = item }
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color.appBackground)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    estimatedMeals = []
                    errorMessage = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                selectedImage = image
                estimatedMeals = []
                errorMessage = nil
                showCamera = false
            }
        }
        .sheet(item: $showConfirmSheet) { estimate in
            PhotoEstimateConfirmSheet(estimate: estimate, meal: selectedMeal)
                .environmentObject(authManager)
        }
    }

    private func analyzePhoto() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        estimatedMeals = []
        Task {
            do {
                let results = try await PhotoMealAnalyzer.analyze(image: image)
                estimatedMeals = results
                if results.isEmpty { errorMessage = "No food items detected. Try a clearer photo." }
            } catch {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
            }
            isAnalyzing = false
        }
    }
}

struct PhotoMealEstimate: Identifiable {
    let id = UUID()
    let foodName: String
    let servingDescription: String
    let estimatedKcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct PhotoMealEstimateCard: View {
    let estimate: PhotoMealEstimate
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(estimate.foodName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text(estimate.servingDescription)
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
                HStack(spacing: 10) {
                    Text("\(estimate.estimatedKcal) kcal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.appAccent)
                    Text("\(Int(estimate.proteinG))g P")
                        .font(.system(size: 12)).foregroundColor(Color.appTextSecondary)
                    Text("\(Int(estimate.carbsG))g C")
                        .font(.system(size: 12)).foregroundColor(Color.appTextSecondary)
                    Text("\(Int(estimate.fatG))g F")
                        .font(.system(size: 12)).foregroundColor(Color.appTextSecondary)
                }
            }
            Spacer()
            Button(action: onLog) {
                Text("Log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.appAccent)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct PhotoEstimateConfirmSheet: View {
    let estimate: PhotoMealEstimate
    let meal: FoodMeal
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var kcalText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    init(estimate: PhotoMealEstimate, meal: FoodMeal) {
        self.estimate = estimate
        self.meal = meal
        _kcalText    = State(initialValue: "\(estimate.estimatedKcal)")
        _proteinText = State(initialValue: String(format: "%.1f", estimate.proteinG))
        _carbsText   = State(initialValue: String(format: "%.1f", estimate.carbsG))
        _fatText     = State(initialValue: String(format: "%.1f", estimate.fatG))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Food Item") {
                    Text(estimate.foodName).font(.system(size: 16, weight: .semibold))
                    Text(estimate.servingDescription).font(.system(size: 13)).foregroundColor(Color.appTextTertiary)
                }
                Section("Macros (edit if needed)") {
                    HStack {
                        Text("Calories").foregroundColor(Color.appTextSecondary)
                        Spacer()
                        TextField("kcal", text: $kcalText).multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Protein (g)").foregroundColor(Color.appTextSecondary)
                        Spacer()
                        TextField("g", text: $proteinText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Carbs (g)").foregroundColor(Color.appTextSecondary)
                        Spacer()
                        TextField("g", text: $carbsText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Fat (g)").foregroundColor(Color.appTextSecondary)
                        Spacer()
                        TextField("g", text: $fatText).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Confirm & Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { logFood() }.font(.system(size: 15, weight: .bold))
                }
            }
        }
    }

    private func logFood() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        let entry = LocalFoodLog(
            userId: userId,
            foodName: estimate.foodName,
            kcal: Int(kcalText) ?? estimate.estimatedKcal,
            proteinG: Double(proteinText) ?? estimate.proteinG,
            carbsG: Double(carbsText) ?? estimate.carbsG,
            fatG: Double(fatText) ?? estimate.fatG,
            source: "photo_ai",
            mealWindow: meal.rawValue
        )
        entry.servingQty = 1
        entry.servingUnit = estimate.servingDescription
        ctx.insert(entry)
        try? ctx.save()
        Task { await SyncService.shared.pushFoodLog(entry, context: ctx) }
        dismiss()
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

enum PhotoMealAnalyzer {
    static func analyze(image: UIImage) async throws -> [PhotoMealEstimate] {
        guard let session = try? await supabase.auth.session else {
            throw URLError(.userAuthenticationRequired)
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw URLError(.cannotDecodeContentData)
        }
        let base64Image = imageData.base64EncodedString()
        guard let url = URL(string: "https://sgbszuimvqxzqvmgvyrn.supabase.co/functions/v1/pepper-chat") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let prompt = """
Analyze the food in this photo. Return ONLY a valid JSON array, no other text:
[{"foodName":"...","servingDescription":"...","estimatedKcal":0,"proteinG":0.0,"carbsG":0.0,"fatG":0.0}]
Identify 1-5 food items visible. Estimate realistic portion sizes from visual cues. If no food visible, return [].
"""
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]],
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)

        struct ClaudeResponse: Decodable {
            struct Content: Decodable { let type: String; let text: String? }
            let content: [Content]
        }
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = response.content.first(where: { $0.type == "text" })?.text else { return [] }

        struct RawEstimate: Decodable {
            let foodName: String
            let servingDescription: String
            let estimatedKcal: Int
            let proteinG: Double
            let carbsG: Double
            let fatG: Double
        }
        let jsonStr = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = jsonStr.data(using: .utf8) else { return [] }
        let raw = (try? JSONDecoder().decode([RawEstimate].self, from: jsonData)) ?? []
        return raw.map { PhotoMealEstimate(foodName: $0.foodName, servingDescription: $0.servingDescription, estimatedKcal: $0.estimatedKcal, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG) }
    }
}
