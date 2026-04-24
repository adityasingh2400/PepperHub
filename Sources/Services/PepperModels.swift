import Foundation

// MARK: - UI Display Models

struct PepperMessage: Identifiable, Sendable {
    let id = UUID()
    let isUser: Bool
    var text: String = ""
    var toolCall: PepperToolCall? = nil
    var toolStatus: ToolStatus = .none

    enum ToolStatus: Sendable {
        case none
        case pending
        case confirmed(String)
        case cancelled
        case failed(String)
    }
}

struct PepperToolCall: Identifiable, Sendable {
    let id = UUID()
    let toolUseId: String
    let toolName: String
    var input: PepperToolInput
    let isReadOnly: Bool

    var displaySummary: String {
        switch input {
        case .logFood(let i):
            return "Log \(i.foodName) for \(i.meal) — \(i.estimatedKcal) kcal, \(Int(i.proteinG))g protein"
        case .logDose(let i):
            return "Log \(i.doseAmount)\(i.doseUnit) \(i.compoundName)\(i.injectionSite.map { " @ \($0)" } ?? "")"
        case .searchFood(let i):
            return "Search foods: \"\(i.query)\""
        case .logExerciseSet(let i):
            return "Log \(i.exerciseName) — \(i.reps) reps @ \(i.weightLbs) lbs"
        case .logSideEffect(let i):
            return "Log side effect: \(i.symptom) (\(i.severity)/10 severity)"
        case .createWorkoutRoutine(let i):
            return "Create routine \"\(i.routineName)\" — \(i.exercises.count) exercise\(i.exercises.count == 1 ? "" : "s")"
        case .navigateTab(let i):
            return "Open \(i.tab) tab"
        case .openCompound(let i):
            return "Open \(i.compoundName)"
        case .openDosingCalc(let i):
            return "Open dosing calculator for \(i.compoundName)"
        case .openPinningProto(let i):
            return "Open pinning protocol for \(i.compoundName)"
        case .openInjectionTracker:
            return "Open injection site tracker"
        case .spotlight(let i):
            return "Highlight \(i.anchorId)"
        }
    }
}

// MARK: - Typed Tool Inputs

enum PepperToolInput: Sendable {
    case logFood(LogFoodInput)
    case logDose(LogDoseInput)
    case searchFood(SearchFoodInput)
    case logExerciseSet(LogExerciseSetInput)
    case logSideEffect(LogSideEffectInput)
    case createWorkoutRoutine(CreateWorkoutRoutineInput)
    case navigateTab(NavigateTabInput)
    case openCompound(OpenCompoundInput)
    case openDosingCalc(OpenCompoundInput)
    case openPinningProto(OpenCompoundInput)
    case openInjectionTracker(OpenInjectionTrackerInput)
    case spotlight(SpotlightInput)
}

struct NavigateTabInput: Codable, Sendable {
    let tab: String  // "today" | "food" | "protocol" | "track" | "research"
}

struct OpenCompoundInput: Codable, Sendable {
    let compoundName: String
}

struct OpenInjectionTrackerInput: Codable, Sendable {}

struct SpotlightInput: Codable, Sendable {
    let anchorId: String
}

struct LogFoodInput: Codable, Sendable {
    let foodName: String
    let meal: String
    let estimatedKcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let qty: Double
    let unit: String
}

struct LogDoseInput: Codable, Sendable {
    let compoundName: String
    let doseAmount: Double
    let doseUnit: String
    let injectionSite: String?
    let notes: String?
}

struct SearchFoodInput: Codable, Sendable {
    let query: String
}

struct LogExerciseSetInput: Codable, Sendable {
    let exerciseName: String
    let muscleGroup: String
    let reps: Int
    let weightLbs: Double
}

struct LogSideEffectInput: Codable, Sendable {
    let symptom: String
    let severity: Int
    let linkedCompound: String?
}

struct RoutineExerciseInput: Codable, Sendable {
    let exerciseName: String
    let muscleGroup: String
    let targetSets: Int
    let targetReps: Int
    let targetWeightLbs: Double
}

struct CreateWorkoutRoutineInput: Codable, Sendable {
    let routineName: String
    let exercises: [RoutineExerciseInput]
}

// MARK: - API History (main-actor-only wire format)

enum PepperHistoryContent {
    case userText(String)
    case assistantText(String)
    case assistantWithTool(text: String?, toolUseId: String, toolName: String, inputData: Data)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    func toAPIDict() -> [String: Any] {
        switch self {
        case .userText(let text):
            return ["role": "user", "content": text]

        case .assistantText(let text):
            return ["role": "assistant", "content": [["type": "text", "text": text]]]

        case .assistantWithTool(let text, let toolUseId, let toolName, let inputData):
            var blocks: [[String: Any]] = []
            if let t = text, !t.isEmpty {
                blocks.append(["type": "text", "text": t])
            }
            let inputObj = (try? JSONSerialization.jsonObject(with: inputData)) ?? [String: Any]()
            blocks.append(["type": "tool_use", "id": toolUseId, "name": toolName, "input": inputObj])
            return ["role": "assistant", "content": blocks]

        case .toolResult(let toolUseId, let content, let isError):
            return ["role": "user", "content": [[
                "type": "tool_result",
                "tool_use_id": toolUseId,
                "content": content,
                "is_error": isError
            ]]]
        }
    }

    var isTurnStart: Bool {
        if case .userText = self { return true }
        return false
    }

    var isTurnEnd: Bool {
        if case .assistantText = self { return true }
        return false
    }
}

// MARK: - Tool Definitions for Claude API

nonisolated(unsafe) let pepperToolDefinitions: [[String: Any]] = [
    [
        "name": "log_food_entry",
        "description": "Log a food item to the user's food log for today. Use search_food first if you're unsure of the exact macros.",
        "input_schema": [
            "type": "object",
            "properties": [
                "foodName": ["type": "string", "description": "Name of the food item"],
                "meal": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"], "description": "Meal time"],
                "estimatedKcal": ["type": "integer", "description": "Estimated calories"],
                "proteinG": ["type": "number", "description": "Protein in grams"],
                "carbsG": ["type": "number", "description": "Carbohydrates in grams"],
                "fatG": ["type": "number", "description": "Fat in grams"],
                "qty": ["type": "number", "description": "Quantity"],
                "unit": ["type": "string", "enum": ["g", "oz", "ml", "serving", "piece"], "description": "Unit of measurement"]
            ],
            "required": ["foodName", "meal", "estimatedKcal", "proteinG", "carbsG", "fatG", "qty", "unit"]
        ]
    ],
    [
        "name": "log_dose",
        "description": "Log a peptide/compound dose for the user.",
        "input_schema": [
            "type": "object",
            "properties": [
                "compoundName": ["type": "string", "description": "Name of the compound (must match user's protocol)"],
                "doseAmount": ["type": "number", "description": "Dose amount"],
                "doseUnit": ["type": "string", "enum": ["mcg", "mg", "iu"], "description": "Unit of dose"],
                "injectionSite": ["type": "string", "description": "Injection site (e.g. 'left abdomen')"],
                "notes": ["type": "string", "description": "Optional notes"]
            ],
            "required": ["compoundName", "doseAmount", "doseUnit"]
        ]
    ],
    [
        "name": "search_food",
        "description": "Search for food items to get accurate macro data. Returns up to 5 candidates. Use this before log_food_entry when you need accurate nutritional data.",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Food search query"]
            ],
            "required": ["query"]
        ]
    ],
    [
        "name": "log_exercise_set",
        "description": "Log a single exercise set to today's workout.",
        "input_schema": [
            "type": "object",
            "properties": [
                "exerciseName": ["type": "string", "description": "Name of the exercise"],
                "muscleGroup": ["type": "string", "enum": ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio", "Other"], "description": "Primary muscle group"],
                "reps": ["type": "integer", "description": "Number of reps"],
                "weightLbs": ["type": "number", "description": "Weight in pounds (0 for bodyweight)"]
            ],
            "required": ["exerciseName", "muscleGroup", "reps", "weightLbs"]
        ]
    ],
    [
        "name": "log_side_effect",
        "description": "Log a side effect or symptom the user experienced.",
        "input_schema": [
            "type": "object",
            "properties": [
                "symptom": ["type": "string", "description": "Description of the symptom"],
                "severity": ["type": "integer", "description": "Severity from 1 (mild) to 10 (severe)"],
                "linkedCompound": ["type": "string", "description": "Compound name to link this to (optional, from user's protocol)"]
            ],
            "required": ["symptom", "severity"]
        ]
    ],
    [
        "name": "create_workout_routine",
        "description": "Create a named workout routine with a list of exercises. Use this when the user asks to build or save a workout plan (e.g. 'create a push day', 'make me a leg routine').",
        "input_schema": [
            "type": "object",
            "properties": [
                "routineName": ["type": "string", "description": "Name of the routine (e.g. 'Push Day', 'Leg Day A')"],
                "exercises": [
                    "type": "array",
                    "description": "Ordered list of exercises in the routine",
                    "items": [
                        "type": "object",
                        "properties": [
                            "exerciseName": ["type": "string", "description": "Name of the exercise"],
                            "muscleGroup": ["type": "string", "enum": ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio", "Other"], "description": "Primary muscle group"],
                            "targetSets": ["type": "integer", "description": "Number of sets"],
                            "targetReps": ["type": "integer", "description": "Target reps per set"],
                            "targetWeightLbs": ["type": "number", "description": "Starting weight in lbs (0 for bodyweight)"]
                        ],
                        "required": ["exerciseName", "muscleGroup", "targetSets", "targetReps", "targetWeightLbs"]
                    ]
                ]
            ],
            "required": ["routineName", "exercises"]
        ]
    ],
    [
        "name": "navigate_to_tab",
        "description": "Switch the user to a tab in the app. Use when the user asks to see a section by name.",
        "input_schema": [
            "type": "object",
            "properties": [
                "tab": ["type": "string", "enum": ["today", "food", "protocol", "track", "research"], "description": "Which tab to open"]
            ],
            "required": ["tab"]
        ]
    ],
    [
        "name": "open_compound",
        "description": "Open a specific peptide/compound detail view. Use when the user mentions a compound by name.",
        "input_schema": [
            "type": "object",
            "properties": [
                "compoundName": ["type": "string", "description": "Compound name (canonical or alias), e.g. 'BPC-157', 'Tirzepatide', 'MOTS-C'"]
            ],
            "required": ["compoundName"]
        ]
    ],
    [
        "name": "open_dosing_calculator",
        "description": "Open the dosing calculator for a compound. Use when the user asks how much to take, or for a dose calculation.",
        "input_schema": [
            "type": "object",
            "properties": [
                "compoundName": ["type": "string", "description": "Compound name"]
            ],
            "required": ["compoundName"]
        ]
    ],
    [
        "name": "open_pinning_protocol",
        "description": "Open the pinning / injection site protocol for a compound. Use when the user asks how or where to inject.",
        "input_schema": [
            "type": "object",
            "properties": [
                "compoundName": ["type": "string", "description": "Compound name"]
            ],
            "required": ["compoundName"]
        ]
    ],
    [
        "name": "open_injection_tracker",
        "description": "Open the app's 3D Injection Site Tracker. Use when the user asks to open, show, see, or tell them about the injection site tracker, injection sites, or site rotation.",
        "input_schema": [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    ],
    [
        "name": "spotlight_element",
        "description": "Draw a pulsating highlight ring around a specific element on the current screen to point the user's attention at it. Use AFTER navigating to the relevant page. Only use anchor IDs that have been registered in the app.",
        "input_schema": [
            "type": "object",
            "properties": [
                "anchorId": ["type": "string", "description": "Anchor ID of the element to highlight"]
            ],
            "required": ["anchorId"]
        ]
    ]
]
