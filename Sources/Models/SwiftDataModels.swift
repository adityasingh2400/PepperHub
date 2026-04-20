import SwiftData
import Foundation

// MARK: - Protocol

@Model
final class LocalProtocol {
    var id: UUID
    var userId: String
    var name: String
    var isActive: Bool
    var startDate: Date
    var endDate: Date?
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var compounds: [LocalProtocolCompound] = []

    init(userId: String, name: String) {
        self.id = UUID()
        self.userId = userId
        self.name = name
        self.isActive = true
        self.startDate = .now
        self.createdAt = .now
    }
}

@Model
final class LocalProtocolCompound {
    var id: UUID
    var protocolId: UUID
    var compoundName: String
    var doseMcg: Double
    var frequency: String  // "daily","eod","3x_weekly","2x_weekly","weekly","5on_2off","mwf","custom"
    var doseTimesRaw: String  // JSON-encoded ["07:00","21:00"]
    var customDays: [Int]

    var doseTimes: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(doseTimesRaw.utf8))) ?? [] }
        set { doseTimesRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    init(protocolId: UUID, compoundName: String, doseMcg: Double, frequency: String, doseTimes: [String]) {
        self.id = UUID()
        self.protocolId = protocolId
        self.compoundName = compoundName
        self.doseMcg = doseMcg
        self.frequency = frequency
        self.doseTimesRaw = (try? String(data: JSONEncoder().encode(doseTimes), encoding: .utf8)) ?? "[]"
        self.customDays = []
    }
}

// MARK: - Dose Log

@Model
final class LocalDoseLog {
    var id: UUID
    var userId: String
    var compoundName: String
    var protocolId: UUID?
    var dosedAt: Date
    var doseMcg: Double
    var injectionSite: String
    var vialId: UUID?
    var notes: String
    var syncedAt: Date?
    var updatedAt: Date

    init(userId: String, compoundName: String, dosedAt: Date = .now, doseMcg: Double, injectionSite: String = "", notes: String = "") {
        self.id = UUID()
        self.userId = userId
        self.compoundName = compoundName
        self.dosedAt = dosedAt
        self.doseMcg = doseMcg
        self.injectionSite = injectionSite
        self.notes = notes
        self.updatedAt = .now
    }
}

// MARK: - Vial

@Model
final class LocalVial {
    var id: UUID
    var userId: String
    var compoundName: String
    var totalMg: Double
    var bacWaterMl: Double
    var concentrationMcgPerUnit: Double  // mcg per 0.1 mL (1 IU on insulin syringe)
    var unitsRemaining: Double
    var purchasedAt: Date
    var syncedAt: Date?

    var percentRemaining: Double {
        let initial = bacWaterMl * 10
        guard initial > 0 else { return 0 }
        return min(1, unitsRemaining / initial)
    }

    init(userId: String, compoundName: String, totalMg: Double, bacWaterMl: Double) {
        self.id = UUID()
        self.userId = userId
        self.compoundName = compoundName
        self.totalMg = totalMg
        self.bacWaterMl = bacWaterMl
        // concentration: (totalMg * 1000 mcg) / (bacWaterMl * 10 units) = mcg per unit
        self.concentrationMcgPerUnit = (totalMg * 1000.0) / (bacWaterMl * 10.0)
        self.unitsRemaining = bacWaterMl * 10.0
        self.purchasedAt = .now
    }
}

// MARK: - Food Log

@Model
final class LocalFoodLog {
    var id: UUID
    var userId: String
    var loggedAt: Date
    var foodName: String
    var barcode: String?
    var kcal: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var satFatG: Double?
    var sodiumMg: Double?
    var source: String  // "barcode","manual"
    var mealWindow: String  // "pre_dose","post_dose","free"
    var servingQty: Double
    var servingUnit: String
    var syncedAt: Date?
    var updatedAt: Date

    init(userId: String, foodName: String, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double, source: String = "manual", mealWindow: String = "free", barcode: String? = nil) {
        self.id = UUID()
        self.userId = userId
        self.loggedAt = .now
        self.foodName = foodName
        self.barcode = barcode
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.source = source
        self.mealWindow = mealWindow
        self.servingQty = 1
        self.servingUnit = ""
        self.updatedAt = .now
    }
}

// MARK: - Food Cache

@Model
final class CachedFood {
    var barcode: String
    var foodName: String
    var kcal: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var satFatG: Double?
    var sodiumMg: Double?
    var servingQty: Double
    var servingUnit: String
    var cachedAt: Date

    init(barcode: String, foodName: String, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double, servingQty: Double = 1, servingUnit: String = "serving") {
        self.barcode = barcode
        self.foodName = foodName
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.servingQty = servingQty
        self.servingUnit = servingUnit
        self.cachedAt = .now
    }
}

// MARK: - Side Effect Log

@Model
final class LocalSideEffectLog {
    var id: UUID
    var userId: String
    var loggedAt: Date
    var symptom: String
    var severity: Int
    var notes: String
    var linkedDoseId: UUID?
    var linkedCompoundName: String?
    var autoLinked: Bool
    var syncedAt: Date?

    init(userId: String, symptom: String, severity: Int, notes: String = "", linkedDoseId: UUID? = nil, linkedCompoundName: String? = nil, autoLinked: Bool = false) {
        self.id = UUID()
        self.userId = userId
        self.loggedAt = .now
        self.symptom = symptom
        self.severity = severity
        self.notes = notes
        self.linkedDoseId = linkedDoseId
        self.linkedCompoundName = linkedCompoundName
        self.autoLinked = autoLinked
    }
}

// MARK: - Timing Rule Cache

@Model
final class CachedTimingRule {
    var compoundName: String
    var preDoseWindowMins: Int
    var postDoseWindowMins: Int
    var carbLimitG: Int   // -1 means no restriction
    var fatLimitG: Int    // -1 means no restriction
    var warningText: String
    var cachedAt: Date

    var hasCarbRestriction: Bool { carbLimitG >= 0 }
    var hasFatRestriction: Bool { fatLimitG >= 0 }

    init(compoundName: String, preDose: Int, postDose: Int, carbLimit: Int, fatLimit: Int, warning: String) {
        self.compoundName = compoundName
        self.preDoseWindowMins = preDose
        self.postDoseWindowMins = postDose
        self.carbLimitG = carbLimit
        self.fatLimitG = fatLimit
        self.warningText = warning
        self.cachedAt = .now
    }
}

// MARK: - User Profile Cache

@Model
final class CachedUserProfile {
    var userId: String
    var weightKg: Double
    var heightCm: Double
    var ageYears: Int
    var biologicalSex: String
    var activityLevel: String
    var goal: String
    var experience: String = ""
    var trainingDaysPerWeek: Int = 0
    var eatingStyle: String = ""
    var hasProtocol: Bool = false
    var protocolCompounds: [String] = []
    var rmrKcal: Double
    var tdeeKcal: Double
    var calorieTargetKcal: Double = 0.0
    var macroGoalProteinG: Int
    var macroGoalCarbsG: Int
    var macroGoalFatG: Int
    var timezone: String
    var cachedAt: Date

    init(userId: String, weightKg: Double, heightCm: Double, ageYears: Int,
         biologicalSex: String, activityLevel: String, goal: String,
         experience: String, trainingDaysPerWeek: Int, eatingStyle: String,
         hasProtocol: Bool, protocolCompounds: [String],
         rmrKcal: Double, tdeeKcal: Double, calorieTargetKcal: Double,
         proteinG: Int, carbsG: Int, fatG: Int) {
        self.userId = userId
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
        self.activityLevel = activityLevel
        self.goal = goal
        self.experience = experience
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.eatingStyle = eatingStyle
        self.hasProtocol = hasProtocol
        self.protocolCompounds = protocolCompounds
        self.rmrKcal = rmrKcal
        self.tdeeKcal = tdeeKcal
        self.calorieTargetKcal = calorieTargetKcal
        self.macroGoalProteinG = proteinG
        self.macroGoalCarbsG = carbsG
        self.macroGoalFatG = fatG
        self.timezone = TimeZone.current.identifier
        self.cachedAt = .now
    }
}

// MARK: - Workout Log

@Model
final class LocalWorkout {
    var id: UUID
    var userId: String
    var loggedAt: Date
    var type: String        // "strength", "cardio", "hiit", "mobility", "sport", "other"
    var durationMinutes: Int
    var caloriesBurned: Int = 0
    var notes: String
    var syncedAt: Date?

    init(userId: String, type: String, durationMinutes: Int, caloriesBurned: Int = 0, notes: String = "") {
        self.id = UUID()
        self.userId = userId
        self.loggedAt = .now
        self.type = type
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.notes = notes
    }
}

// MARK: - Exercise Logging

@Model
final class LocalExerciseLog {
    var id: UUID
    var userId: String
    var exerciseName: String
    var muscleGroup: String
    var loggedAt: Date

    init(userId: String, exerciseName: String, muscleGroup: String) {
        self.id = UUID()
        self.userId = userId
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.loggedAt = .now
    }
}

@Model
final class LocalWorkoutSet {
    var id: UUID
    var exerciseLogId: UUID
    var setNumber: Int
    var reps: Int
    var weightLbs: Double

    init(exerciseLogId: UUID, setNumber: Int, reps: Int, weightLbs: Double) {
        self.id = UUID()
        self.exerciseLogId = exerciseLogId
        self.setNumber = setNumber
        self.reps = reps
        self.weightLbs = weightLbs
    }
}

// MARK: - Routines

@Model
final class LocalRoutine {
    var id: UUID
    var userId: String
    var name: String
    var createdAt: Date

    init(userId: String, name: String) {
        self.id = UUID()
        self.userId = userId
        self.name = name
        self.createdAt = .now
    }
}

@Model
final class LocalRoutineExercise {
    var id: UUID
    var routineId: UUID
    var exerciseName: String
    var muscleGroup: String
    var targetSets: Int
    var targetReps: Int
    var targetWeightLbs: Double
    var order: Int

    init(routineId: UUID, exerciseName: String, muscleGroup: String,
         targetSets: Int = 3, targetReps: Int = 10, targetWeightLbs: Double = 0, order: Int = 0) {
        self.id = UUID()
        self.routineId = routineId
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightLbs = targetWeightLbs
        self.order = order
    }

    var muscleGroupColorHex: String {
        switch muscleGroup {
        case "Chest":     return "ef4444"
        case "Back":      return "3b82f6"
        case "Legs":      return "10b981"
        case "Shoulders": return "f59e0b"
        case "Arms":      return "8b5cf6"
        case "Core":      return "f97316"
        case "Cardio":    return "ec4899"
        default:          return "6b7280"
        }
    }

    var muscleGroupIcon: String {
        switch muscleGroup {
        case "Chest":     return "figure.strengthtraining.traditional"
        case "Back":      return "figure.strengthtraining.functional"
        case "Legs":      return "figure.run"
        case "Shoulders": return "figure.arms.open"
        case "Arms":      return "dumbbell.fill"
        case "Core":      return "figure.core.training"
        case "Cardio":    return "heart.fill"
        default:          return "figure.mixed.cardio"
        }
    }
}
