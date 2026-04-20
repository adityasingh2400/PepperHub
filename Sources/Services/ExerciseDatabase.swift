import Foundation

struct ExerciseDefinition: Identifiable {
    let id = UUID()
    let name: String
    let muscleGroup: String
    let equipment: String
}

struct ExerciseDatabase {
    static let all: [ExerciseDefinition] = [
        // Chest
        ExerciseDefinition(name: "Bench Press", muscleGroup: "Chest", equipment: "Barbell"),
        ExerciseDefinition(name: "Incline Bench Press", muscleGroup: "Chest", equipment: "Barbell"),
        ExerciseDefinition(name: "Decline Bench Press", muscleGroup: "Chest", equipment: "Barbell"),
        ExerciseDefinition(name: "Dumbbell Fly", muscleGroup: "Chest", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Incline Dumbbell Press", muscleGroup: "Chest", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Cable Fly", muscleGroup: "Chest", equipment: "Cable"),
        ExerciseDefinition(name: "Push-Up", muscleGroup: "Chest", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Dip", muscleGroup: "Chest", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Chest Press Machine", muscleGroup: "Chest", equipment: "Machine"),
        // Back
        ExerciseDefinition(name: "Deadlift", muscleGroup: "Back", equipment: "Barbell"),
        ExerciseDefinition(name: "Barbell Row", muscleGroup: "Back", equipment: "Barbell"),
        ExerciseDefinition(name: "Pull-Up", muscleGroup: "Back", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Chin-Up", muscleGroup: "Back", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Lat Pulldown", muscleGroup: "Back", equipment: "Cable"),
        ExerciseDefinition(name: "Seated Cable Row", muscleGroup: "Back", equipment: "Cable"),
        ExerciseDefinition(name: "T-Bar Row", muscleGroup: "Back", equipment: "Barbell"),
        ExerciseDefinition(name: "Face Pull", muscleGroup: "Back", equipment: "Cable"),
        ExerciseDefinition(name: "Dumbbell Row", muscleGroup: "Back", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Hyperextension", muscleGroup: "Back", equipment: "Bodyweight"),
        // Legs
        ExerciseDefinition(name: "Squat", muscleGroup: "Legs", equipment: "Barbell"),
        ExerciseDefinition(name: "Romanian Deadlift", muscleGroup: "Legs", equipment: "Barbell"),
        ExerciseDefinition(name: "Leg Press", muscleGroup: "Legs", equipment: "Machine"),
        ExerciseDefinition(name: "Hack Squat", muscleGroup: "Legs", equipment: "Machine"),
        ExerciseDefinition(name: "Lunge", muscleGroup: "Legs", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Bulgarian Split Squat", muscleGroup: "Legs", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Leg Extension", muscleGroup: "Legs", equipment: "Machine"),
        ExerciseDefinition(name: "Leg Curl", muscleGroup: "Legs", equipment: "Machine"),
        ExerciseDefinition(name: "Calf Raise", muscleGroup: "Legs", equipment: "Machine"),
        ExerciseDefinition(name: "Hip Thrust", muscleGroup: "Legs", equipment: "Barbell"),
        ExerciseDefinition(name: "Goblet Squat", muscleGroup: "Legs", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Step Up", muscleGroup: "Legs", equipment: "Dumbbell"),
        // Shoulders
        ExerciseDefinition(name: "Overhead Press", muscleGroup: "Shoulders", equipment: "Barbell"),
        ExerciseDefinition(name: "Dumbbell Shoulder Press", muscleGroup: "Shoulders", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Arnold Press", muscleGroup: "Shoulders", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Lateral Raise", muscleGroup: "Shoulders", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Cable Lateral Raise", muscleGroup: "Shoulders", equipment: "Cable"),
        ExerciseDefinition(name: "Front Raise", muscleGroup: "Shoulders", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Rear Delt Fly", muscleGroup: "Shoulders", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Upright Row", muscleGroup: "Shoulders", equipment: "Barbell"),
        ExerciseDefinition(name: "Shrug", muscleGroup: "Shoulders", equipment: "Barbell"),
        // Arms
        ExerciseDefinition(name: "Barbell Curl", muscleGroup: "Arms", equipment: "Barbell"),
        ExerciseDefinition(name: "Dumbbell Curl", muscleGroup: "Arms", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Hammer Curl", muscleGroup: "Arms", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Preacher Curl", muscleGroup: "Arms", equipment: "Barbell"),
        ExerciseDefinition(name: "Cable Curl", muscleGroup: "Arms", equipment: "Cable"),
        ExerciseDefinition(name: "Tricep Pushdown", muscleGroup: "Arms", equipment: "Cable"),
        ExerciseDefinition(name: "Skull Crusher", muscleGroup: "Arms", equipment: "Barbell"),
        ExerciseDefinition(name: "Close Grip Bench Press", muscleGroup: "Arms", equipment: "Barbell"),
        ExerciseDefinition(name: "Overhead Tricep Extension", muscleGroup: "Arms", equipment: "Dumbbell"),
        ExerciseDefinition(name: "Tricep Kickback", muscleGroup: "Arms", equipment: "Dumbbell"),
        // Core
        ExerciseDefinition(name: "Plank", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Crunch", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Hanging Leg Raise", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Russian Twist", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Ab Wheel Rollout", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Cable Crunch", muscleGroup: "Core", equipment: "Cable"),
        ExerciseDefinition(name: "Leg Raise", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Sit-Up", muscleGroup: "Core", equipment: "Bodyweight"),
        ExerciseDefinition(name: "Mountain Climber", muscleGroup: "Core", equipment: "Bodyweight"),
        // Cardio
        ExerciseDefinition(name: "Running", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Cycling", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Rowing Machine", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Elliptical", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Jump Rope", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Swimming", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "Stair Climber", muscleGroup: "Cardio", equipment: "Cardio"),
        ExerciseDefinition(name: "HIIT", muscleGroup: "Cardio", equipment: "Cardio"),
    ]

    static func search(_ query: String) -> [ExerciseDefinition] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || $0.muscleGroup.lowercased().contains(q) }
    }
}

extension ExerciseDefinition {
    var muscleGroupColor: String {
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
