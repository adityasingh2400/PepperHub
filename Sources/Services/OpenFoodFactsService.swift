import Foundation
import SwiftData

struct FoodServingOption: Sendable {
    let label: String   // e.g. "1 large", "1 cup"
    let grams: Double
}

struct FoodItem: Sendable, Identifiable {
    var id: String { barcode.isEmpty ? name : barcode }
    let barcode: String
    let name: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let fiberPer100g: Double?
    let sugarPer100g: Double?
    let satFatPer100g: Double?
    let sodiumPer100g: Double?
    let servingQty: Double
    let servingUnit: String
    var servingOptions: [FoodServingOption] = []
}

@MainActor
final class OpenFoodFactsService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Evict stale cache entries (>30 days old). Call on app foreground.
    func evictStaleCache() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let descriptor = FetchDescriptor<CachedFood>(
            predicate: #Predicate { $0.cachedAt < cutoff }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            stale.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
    }

    func lookup(barcode: String) async throws -> FoodItem? {
        // 1. Check cache
        if let cached = cachedItem(barcode: barcode) {
            return cached
        }

        // 2. Fetch from API (5 second timeout)
        let urlStr = "https://world.openfoodfacts.org/api/v3/product/\(barcode).json"
        guard let url = URL(string: urlStr) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("PeptideApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let item = parseResponse(data: data, barcode: barcode) else { return nil }

        // 3. Cache result
        cacheItem(item)
        return item
    }

    func search(query: String) async throws -> [FoodItem] {
        // USDA (whole foods) + OpenFoodFacts (packaged) in parallel
        async let usdaTask = searchUSDA(query: query)
        async let offTask  = searchOFF(query: query)

        let usda = (try? await usdaTask) ?? []
        let off  = (try? await offTask)  ?? []

        var seen = Set<String>()
        return (usda + off).filter { seen.insert($0.name.lowercased()).inserted }
    }

    // MARK: - USDA FoodData Central

    private func searchUSDA(query: String) async throws -> [FoodItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // DEMO_KEY: 30 req/hour — replace with a free key from https://fdc.nal.usda.gov/api-guide.html
        let urlStr = "https://api.nal.usda.gov/fdc/v1/foods/search?query=\(encoded)&api_key=WNzovxJ2aTXZ09YiNaAXzgeQiJiboVpoWIWMinwU&pageSize=15&dataType=Foundation,SR%20Legacy,Branded"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("PeptideApp/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseUSDAResponse(data: data)
    }

    private func parseUSDAResponse(data: Data) -> [FoodItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else { return [] }
        return foods.compactMap { food in
            guard let fdcId = food["fdcId"] as? Int,
                  let raw = food["description"] as? String, !raw.isEmpty else { return nil }
            let name = raw.capitalized
            let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
            var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
            for n in nutrients {
                let val = (n["value"] as? Double) ?? 0
                let nid  = n["nutrientId"] as? Int
                let nnum = n["nutrientNumber"] as? String
                if nid == 1008 || nnum == "208" { kcal    = val }
                else if nid == 1003 || nnum == "203" { protein = val }
                else if nid == 1005 || nnum == "205" { carbs   = val }
                else if nid == 1004 || nnum == "204" { fat     = val }
            }
            guard kcal > 0 || protein > 0 else { return nil }

            // Build serving options from foodMeasures
            let measures = food["foodMeasures"] as? [[String: Any]] ?? []
            var options: [FoodServingOption] = measures.compactMap { m in
                guard let label = m["disseminationText"] as? String,
                      let grams = m["gramWeight"] as? Double, grams > 0 else { return nil }
                return FoodServingOption(label: label, grams: grams)
            }
            // Always include 100g reference
            if !options.contains(where: { $0.label == "100 g" }) {
                options.append(FoodServingOption(label: "100 g", grams: 100))
            }

            return FoodItem(
                barcode: "usda:\(fdcId)",
                name: name,
                kcalPer100g: kcal, proteinPer100g: protein,
                carbsPer100g: carbs, fatPer100g: fat,
                fiberPer100g: nil, sugarPer100g: nil, satFatPer100g: nil, sodiumPer100g: nil,
                servingQty: 100, servingUnit: "g",
                servingOptions: options
            )
        }
    }

    // MARK: - OpenFoodFacts (packaged / barcoded products)

    private func searchOFF(query: String) async throws -> [FoodItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=10&lc=en"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("PeptideApp/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseSearchResponse(data: data)
    }

    // MARK: - Private

    private func cachedItem(barcode: String) -> FoodItem? {
        let descriptor = FetchDescriptor<CachedFood>(
            predicate: #Predicate { $0.barcode == barcode }
        )
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        return FoodItem(
            barcode: cached.barcode,
            name: cached.foodName,
            kcalPer100g: Double(cached.kcal),
            proteinPer100g: cached.proteinG,
            carbsPer100g: cached.carbsG,
            fatPer100g: cached.fatG,
            fiberPer100g: cached.fiberG,
            sugarPer100g: cached.sugarG,
            satFatPer100g: cached.satFatG,
            sodiumPer100g: cached.sodiumMg.map { $0 / 10 },  // mg/100g → g/100g for scaling
            servingQty: cached.servingQty,
            servingUnit: cached.servingUnit
        )
    }

    private func cacheItem(_ item: FoodItem) {
        // Delete existing
        let barcode = item.barcode
        let descriptor = FetchDescriptor<CachedFood>(predicate: #Predicate { $0.barcode == barcode })
        if let existing = try? modelContext.fetch(descriptor) {
            existing.forEach { modelContext.delete($0) }
        }
        let cached = CachedFood(
            barcode: item.barcode,
            foodName: item.name,
            kcal: Int(item.kcalPer100g),
            proteinG: item.proteinPer100g,
            carbsG: item.carbsPer100g,
            fatG: item.fatPer100g,
            servingQty: item.servingQty,
            servingUnit: item.servingUnit
        )
        cached.fiberG = item.fiberPer100g
        cached.sugarG = item.sugarPer100g
        cached.satFatG = item.satFatPer100g
        cached.sodiumMg = item.sodiumPer100g.map { $0 * 10 }  // g/100g → mg/100g
        modelContext.insert(cached)
        try? modelContext.save()
    }

    private func parseResponse(data: Data, barcode: String) -> FoodItem? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any] else { return nil }

        let name = (product["product_name"] as? String) ?? (product["product_name_en"] as? String) ?? "Unknown"
        let nutrients = product["nutriments"] as? [String: Any] ?? [:]

        let kcal = nutrientDouble(nutrients, keys: ["energy-kcal_100g", "energy_100g"]) ?? 0
        let protein = nutrientDouble(nutrients, keys: ["proteins_100g"]) ?? 0
        let carbs = nutrientDouble(nutrients, keys: ["carbohydrates_100g"]) ?? 0
        let fat = nutrientDouble(nutrients, keys: ["fat_100g"]) ?? 0

        let servingQty: Double
        let servingUnit: String
        if let sq = product["serving_quantity"] as? Double, sq > 0 {
            servingQty = sq
            servingUnit = (product["serving_size"] as? String) ?? "serving"
        } else if let sqStr = product["serving_quantity"] as? String, let sq = Double(sqStr), sq > 0 {
            servingQty = sq
            servingUnit = (product["serving_size"] as? String) ?? "serving"
        } else {
            servingQty = 100
            servingUnit = "g"
        }

        return FoodItem(
            barcode: barcode,
            name: name,
            kcalPer100g: kcal,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            fiberPer100g: nutrientDouble(nutrients, keys: ["fiber_100g"]),
            sugarPer100g: nutrientDouble(nutrients, keys: ["sugars_100g"]),
            satFatPer100g: nutrientDouble(nutrients, keys: ["saturated-fat_100g"]),
            sodiumPer100g: nutrientDouble(nutrients, keys: ["sodium_100g"]),
            servingQty: servingQty,
            servingUnit: servingUnit
        )
    }

    private func parseSearchResponse(data: Data) -> [FoodItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else { return [] }
        return products.compactMap { product in
            guard let barcode = product["code"] as? String else { return nil }
            return parseProductDict(product, barcode: barcode)
        }.filter { $0.name != "Unknown" && !$0.name.isEmpty }
    }

    private func parseProductDict(_ product: [String: Any], barcode: String) -> FoodItem? {
        let rawName = (product["product_name_en"] as? String)?.trimmingCharacters(in: .whitespaces)
            ?? (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
            ?? ""
        let name = rawName.isEmpty ? "Unknown" : rawName
        let nutrients = product["nutriments"] as? [String: Any] ?? [:]
        let kcal = nutrientDouble(nutrients, keys: ["energy-kcal_100g"]) ?? 0
        let protein = nutrientDouble(nutrients, keys: ["proteins_100g"]) ?? 0
        let carbs = nutrientDouble(nutrients, keys: ["carbohydrates_100g"]) ?? 0
        let fat = nutrientDouble(nutrients, keys: ["fat_100g"]) ?? 0
        return FoodItem(
            barcode: barcode, name: name,
            kcalPer100g: kcal, proteinPer100g: protein, carbsPer100g: carbs, fatPer100g: fat,
            fiberPer100g: nil, sugarPer100g: nil, satFatPer100g: nil, sodiumPer100g: nil,
            servingQty: 100, servingUnit: "g"
        )
    }

    private func nutrientDouble(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let v = dict[key] as? Double { return v }
            if let v = dict[key] as? Int { return Double(v) }
            if let v = dict[key] as? String, let d = Double(v) { return d }
        }
        return nil
    }
}
