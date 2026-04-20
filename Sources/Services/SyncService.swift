import Foundation
import SwiftData
import Supabase

// All SwiftData reads/writes happen on @MainActor.
// All Supabase network calls run in Task.detached (nonisolated) so
// PostgrestResponse (non-Sendable) never crosses an actor boundary.

@MainActor
final class SyncService {
    static let shared = SyncService()
    private init() {}

    // MARK: - Bootstrap

    func bootstrap(userId: String, context: ModelContext) async {
        await fetchTimingRules(context: context)
        await fetchProfile(userId: userId, context: context)
        await fetchProtocols(userId: userId, context: context)
        await pushUnsynced(userId: userId, context: context)
    }

    // MARK: - Fetch timing rules

    func fetchTimingRules(context: ModelContext) async {
        struct Row: Decodable, Sendable {
            let compound_name: String
            let pre_dose_window_mins: Int?
            let post_dose_window_mins: Int?
            let carb_limit_g: Int?
            let fat_limit_g: Int?
            let warning_text: String?
        }
        let rows: [Row] = await Task.detached {
            (try? await supabase.from("peptide_timing_rules").select().execute().value) ?? []
        }.value
        let existing = try? context.fetch(FetchDescriptor<CachedTimingRule>())
        existing?.forEach { context.delete($0) }
        for r in rows {
            context.insert(CachedTimingRule(
                compoundName: r.compound_name,
                preDose:    r.pre_dose_window_mins  ?? -1,
                postDose:   r.post_dose_window_mins ?? -1,
                carbLimit:  r.carb_limit_g          ?? -1,
                fatLimit:   r.fat_limit_g           ?? -1,
                warning:    r.warning_text          ?? ""
            ))
        }
        try? context.save()
    }

    // MARK: - Fetch profile

    func fetchProfile(userId: String, context: ModelContext) async {
        struct Row: Decodable, Sendable {
            let weight_kg: Double?
            let height_cm: Double?
            let age_years: Int?
            let biological_sex: String?
            let activity_level: String?
            let goal: String?
            let experience: String?
            let training_days_per_week: Int?
            let eating_style: String?
            let has_protocol: Bool?
            let protocol_compounds: [String]?
            let rmr_kcal: Double?
            let tdee_kcal: Double?
            let calorie_target_kcal: Double?
            let macro_goal_protein_g: Int?
            let macro_goal_carbs_g: Int?
            let macro_goal_fat_g: Int?
        }
        let uid = userId
        let rows: [Row] = await Task.detached {
            (try? await supabase
                .from("users_profiles")
                .select()
                .eq("user_id", value: uid)
                .limit(1)
                .execute()
                .value) ?? []
        }.value
        guard let r = rows.first,
              let wkg  = r.weight_kg,  let hcm  = r.height_cm,
              let age  = r.age_years,  let sex  = r.biological_sex,
              let act  = r.activity_level, let goal = r.goal,
              let rmr  = r.rmr_kcal,   let tdee = r.tdee_kcal,
              let pro  = r.macro_goal_protein_g,
              let carb = r.macro_goal_carbs_g,
              let fat  = r.macro_goal_fat_g
        else { return }
        let existing = try? context.fetch(FetchDescriptor<CachedUserProfile>())
        existing?.forEach { context.delete($0) }
        context.insert(CachedUserProfile(
            userId:              userId,
            weightKg:            wkg,
            heightCm:            hcm,
            ageYears:            age,
            biologicalSex:       sex,
            activityLevel:       act,
            goal:                goal,
            experience:          r.experience             ?? "",
            trainingDaysPerWeek: r.training_days_per_week ?? 0,
            eatingStyle:         r.eating_style           ?? "",
            hasProtocol:         r.has_protocol           ?? false,
            protocolCompounds:   r.protocol_compounds     ?? [],
            rmrKcal:             rmr,
            tdeeKcal:            tdee,
            calorieTargetKcal:   r.calorie_target_kcal    ?? tdee,
            proteinG:            pro,
            carbsG:              carb,
            fatG:                fat
        ))
        try? context.save()
    }

    // MARK: - Fetch protocols (only if no local data)

    func fetchProtocols(userId: String, context: ModelContext) async {
        let count = (try? context.fetchCount(FetchDescriptor<LocalProtocol>())) ?? 0
        guard count == 0 else { return }

        struct ProtoRow: Decodable, Sendable {
            let id: UUID
            let name: String
            let is_active: Bool
            let start_date: String
            let end_date: String?
        }
        struct CompoundRow: Decodable, Sendable {
            let id: UUID
            let protocol_id: UUID
            let compound_name: String
            let dose_mcg: Double
            let frequency: String
            let dose_times: [String]
        }

        let uid = userId
        let protos: [ProtoRow] = await Task.detached {
            (try? await supabase
                .from("user_protocols")
                .select()
                .eq("user_id", value: uid)
                .eq("is_active", value: true)
                .execute()
                .value) ?? []
        }.value

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        for row in protos {
            let rowId = row.id
            let compounds: [CompoundRow] = await Task.detached {
                (try? await supabase
                    .from("protocol_compounds")
                    .select()
                    .eq("protocol_id", value: rowId.uuidString)
                    .execute()
                    .value) ?? []
            }.value

            let proto = LocalProtocol(userId: userId, name: row.name)
            proto.id = row.id
            proto.isActive = row.is_active
            proto.startDate = df.date(from: row.start_date) ?? .now
            proto.endDate   = row.end_date.flatMap { df.date(from: $0) }
            context.insert(proto)

            for c in compounds {
                let comp = LocalProtocolCompound(
                    protocolId:   c.protocol_id,
                    compoundName: c.compound_name,
                    doseMcg:      c.dose_mcg,
                    frequency:    c.frequency,
                    doseTimes:    c.dose_times
                )
                comp.id = c.id
                context.insert(comp)
                proto.compounds.append(comp)
            }
        }
        try? context.save()
    }

    // MARK: - Push all unsynced

    func pushUnsynced(userId: String, context: ModelContext) async {
        if let logs = try? context.fetch(FetchDescriptor<LocalDoseLog>(
            predicate: #Predicate { $0.syncedAt == nil }
        )) {
            for log in logs { await pushDoseLog(log, context: context) }
        }
        if let logs = try? context.fetch(FetchDescriptor<LocalFoodLog>(
            predicate: #Predicate { $0.syncedAt == nil }
        )) {
            for log in logs { await pushFoodLog(log, context: context) }
        }
        if let logs = try? context.fetch(FetchDescriptor<LocalSideEffectLog>(
            predicate: #Predicate { $0.syncedAt == nil }
        )) {
            for log in logs { await pushSideEffect(log, context: context) }
        }
        if let vials = try? context.fetch(FetchDescriptor<LocalVial>(
            predicate: #Predicate { $0.syncedAt == nil }
        )) {
            for vial in vials { await pushVial(vial, context: context) }
        }
        if let workouts = try? context.fetch(FetchDescriptor<LocalWorkout>(
            predicate: #Predicate { $0.syncedAt == nil }
        )) {
            for w in workouts { await pushWorkout(w, context: context) }
        }
    }

    // MARK: - Push dose log

    func pushDoseLog(_ log: LocalDoseLog, context: ModelContext) async {
        struct P: Encodable, Sendable {
            let id, user_id, compound_name, injection_site, notes: String
            let protocol_id, vial_id: String?
            let dosed_at: Date
            let dose_mcg: Double
        }
        let payload = P(
            id:             log.id.uuidString,
            user_id:        log.userId,
            compound_name:  log.compoundName,
            injection_site: log.injectionSite,
            notes:          log.notes,
            protocol_id:    log.protocolId?.uuidString,
            vial_id:        log.vialId?.uuidString,
            dosed_at:       log.dosedAt,
            dose_mcg:       log.doseMcg
        )
        let ok = await Task.detached {
            (try? await supabase.from("dose_logs").upsert(payload, onConflict: "id").execute()) != nil
        }.value
        if ok { log.syncedAt = .now; try? context.save() }
    }

    // MARK: - Push food log

    func pushFoodLog(_ log: LocalFoodLog, context: ModelContext) async {
        struct P: Encodable, Sendable {
            let id, user_id, food_name, source, meal_window, serving_unit: String
            let barcode: String?
            let logged_at: Date
            let kcal: Int
            let protein_g, carbs_g, fat_g, serving_qty: Double
            let fiber_g, sugar_g, sat_fat_g, sodium_mg: Double?
        }
        let payload = P(
            id:           log.id.uuidString,
            user_id:      log.userId,
            food_name:    log.foodName,
            source:       log.source,
            meal_window:  log.mealWindow,
            serving_unit: log.servingUnit,
            barcode:      log.barcode,
            logged_at:    log.loggedAt,
            kcal:         log.kcal,
            protein_g:    log.proteinG,
            carbs_g:      log.carbsG,
            fat_g:        log.fatG,
            serving_qty:  log.servingQty,
            fiber_g:      log.fiberG,
            sugar_g:      log.sugarG,
            sat_fat_g:    log.satFatG,
            sodium_mg:    log.sodiumMg
        )
        let ok = await Task.detached {
            (try? await supabase.from("food_logs").upsert(payload, onConflict: "id").execute()) != nil
        }.value
        if ok { log.syncedAt = .now; try? context.save() }
    }

    // MARK: - Push workout

    func pushWorkout(_ workout: LocalWorkout, context: ModelContext? = nil) async {
        struct P: Encodable, Sendable {
            let id, user_id, type, notes: String
            let logged_at: Date
            let duration_minutes, calories_burned: Int
        }
        let payload = P(
            id:               workout.id.uuidString,
            user_id:          workout.userId,
            type:             workout.type,
            notes:            workout.notes,
            logged_at:        workout.loggedAt,
            duration_minutes: workout.durationMinutes,
            calories_burned:  workout.caloriesBurned
        )
        let ok = await Task.detached {
            (try? await supabase.from("workouts").upsert(payload, onConflict: "id").execute()) != nil
        }.value
        if ok { workout.syncedAt = .now; if let ctx = context { try? ctx.save() } }
    }

    // MARK: - Push side effect

    func pushSideEffect(_ log: LocalSideEffectLog, context: ModelContext) async {
        struct P: Encodable, Sendable {
            let id, user_id, symptom, notes: String
            let linked_dose_id, linked_compound_name: String?
            let logged_at: Date
            let severity: Int
            let auto_linked: Bool
        }
        let payload = P(
            id:                   log.id.uuidString,
            user_id:              log.userId,
            symptom:              log.symptom,
            notes:                log.notes,
            linked_dose_id:       log.linkedDoseId?.uuidString,
            linked_compound_name: log.linkedCompoundName,
            logged_at:            log.loggedAt,
            severity:             log.severity,
            auto_linked:          log.autoLinked
        )
        let ok = await Task.detached {
            (try? await supabase.from("side_effect_logs").upsert(payload, onConflict: "id").execute()) != nil
        }.value
        if ok { log.syncedAt = .now; try? context.save() }
    }

    // MARK: - Push vial

    func pushVial(_ vial: LocalVial, context: ModelContext? = nil) async {
        struct P: Encodable, Sendable {
            let id, user_id, compound_name: String
            let purchased_at: Date
            let total_mg, bac_water_ml, concentration_mcg_per_unit, units_remaining: Double
        }
        let payload = P(
            id:                         vial.id.uuidString,
            user_id:                    vial.userId,
            compound_name:              vial.compoundName,
            purchased_at:               vial.purchasedAt,
            total_mg:                   vial.totalMg,
            bac_water_ml:               vial.bacWaterMl,
            concentration_mcg_per_unit: vial.concentrationMcgPerUnit,
            units_remaining:            vial.unitsRemaining
        )
        let ok = await Task.detached {
            (try? await supabase.from("vials").upsert(payload, onConflict: "id").execute()) != nil
        }.value
        if ok { vial.syncedAt = .now; if let ctx = context { try? ctx.save() } }
    }

    // MARK: - Push protocol

    func pushProtocol(_ proto: LocalProtocol, userId: String) async {
        struct PP: Encodable, Sendable {
            let id, user_id, name: String
            let is_active: Bool
            let start_date: Date
        }
        struct CP: Encodable, Sendable {
            let id, protocol_id, compound_name, frequency: String
            let dose_mcg: Double
            let dose_times: [String]
        }
        let protoPayload = PP(
            id:         proto.id.uuidString,
            user_id:    userId,
            name:       proto.name,
            is_active:  proto.isActive,
            start_date: proto.startDate
        )
        let compoundPayloads = proto.compounds.map { c in
            CP(id:            c.id.uuidString,
               protocol_id:   proto.id.uuidString,
               compound_name: c.compoundName,
               frequency:     c.frequency,
               dose_mcg:      c.doseMcg,
               dose_times:    c.doseTimes)
        }
        let protoId = proto.id.uuidString
        await Task.detached {
            do {
                try await supabase.from("user_protocols")
                    .update(["is_active": false])
                    .eq("user_id", value: userId)
                    .neq("id", value: protoId)
                    .execute()
                try await supabase.from("user_protocols")
                    .upsert(protoPayload, onConflict: "id")
                    .execute()
                try await supabase.from("protocol_compounds")
                    .delete()
                    .eq("protocol_id", value: protoId)
                    .execute()
                if !compoundPayloads.isEmpty {
                    try await supabase.from("protocol_compounds")
                        .insert(compoundPayloads)
                        .execute()
                }
            } catch {}
        }.value
    }
}
