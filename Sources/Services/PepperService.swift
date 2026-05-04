import Foundation
import SwiftData

@MainActor
final class PepperService: ObservableObject {
    @Published var messages: [PepperMessage] = []
    @Published var isStreaming = false
    @Published var pendingToolCall: PepperToolCall? = nil

    /// Wired by `MainTabView` on appear so nav/spotlight tools can actually
    /// drive the UI. Weak refs to avoid retain cycles with the env objects.
    weak var navigation: NavigationCoordinator?
    weak var spotlight: PepperSpotlight?

    private var apiHistory: [PepperHistoryContent] = []
    private let maxLogicalTurns = 10

    // MARK: - Public API

    func send(userMessage: String, modelContext: ModelContext, userId: String) async {
        guard !isStreaming else { return }

        Analytics.capture(.pepperMessageSent)
        messages.append(PepperMessage(isUser: true, text: userMessage))
        apiHistory.append(.userText(userMessage))

        let systemPrompt = PepperContextBuilder.buildSystemPrompt(userId: userId, modelContext: modelContext)
        await performStream(systemPrompt: systemPrompt, modelContext: modelContext, userId: userId)
    }

    func confirmToolCall(_ call: PepperToolCall, editedInput: PepperToolInput?, modelContext: ModelContext, userId: String) async {
        Analytics.capture(.pepperToolConfirmed, properties: ["tool": call.toolName])
        let finalInput = editedInput ?? call.input
        let finalCall = PepperToolCall(toolUseId: call.toolUseId, toolName: call.toolName, input: finalInput, isReadOnly: call.isReadOnly)

        let resultContent: String
        let isError: Bool

        do {
            resultContent = try await executeTool(finalCall, modelContext: modelContext, userId: userId)
            isError = false
            updateToolStatus(toolUseId: call.toolUseId, status: .confirmed(resultContent))
        } catch {
            resultContent = error.localizedDescription
            isError = true
            updateToolStatus(toolUseId: call.toolUseId, status: .failed(resultContent))
        }

        pendingToolCall = nil
        apiHistory.append(.toolResult(toolUseId: call.toolUseId, content: resultContent, isError: isError))

        let systemPrompt = PepperContextBuilder.buildSystemPrompt(userId: userId, modelContext: modelContext)
        await performStream(systemPrompt: systemPrompt, modelContext: modelContext, userId: userId)
    }

    func cancelToolCall(_ call: PepperToolCall, modelContext: ModelContext, userId: String) async {
        Analytics.capture(.pepperToolCancelled, properties: ["tool": call.toolName])
        updateToolStatus(toolUseId: call.toolUseId, status: .cancelled)
        pendingToolCall = nil
        apiHistory.append(.toolResult(toolUseId: call.toolUseId, content: "{\"error\":\"user cancelled\"}", isError: true))

        let systemPrompt = PepperContextBuilder.buildSystemPrompt(userId: userId, modelContext: modelContext)
        await performStream(systemPrompt: systemPrompt, modelContext: modelContext, userId: userId)
    }

    func clearConversation() {
        messages = []
        apiHistory = []
        pendingToolCall = nil
    }

    // MARK: - Streaming

    private func performStream(systemPrompt: String, modelContext: ModelContext, userId: String) async {
        isStreaming = true
        defer { isStreaming = false }

        let assistantMessage = PepperMessage(isUser: false)
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        do {
            guard let session = try? await supabase.auth.session else {
                messages[messageIndex].text = "Session expired. Please sign in again."
                return
            }

            let url = SupabaseConfiguration.edgeFunctionURL(name: "pepper-chat")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

            let historyDicts = apiHistory.map { $0.toAPIDict() }
            let body: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 2048,
                "stream": true,
                "system": [[
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]],
                "tools": pepperToolDefinitions,
                "messages": historyDicts
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var errorBody = ""
                for try await byte in asyncBytes {
                    errorBody += String(bytes: [byte], encoding: .utf8) ?? ""
                }
                messages[messageIndex].text = "Error \(httpResponse.statusCode): \(errorBody.prefix(200))"
                apiHistory.removeLast() // remove userText we just added
                return
            }

            // SSE state
            var currentText = ""
            var toolBlocks: [Int: (toolUseId: String, toolName: String, partialJSON: String)] = [:]
            var blockTypes: [Int: String] = [:]
            var stopReason = ""

            for try await line in asyncBytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                guard let data = jsonStr.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                let type = event["type"] as? String ?? ""

                switch type {
                case "content_block_start":
                    guard let index = event["index"] as? Int,
                          let block = event["content_block"] as? [String: Any] else { break }
                    let blockType = block["type"] as? String ?? ""
                    blockTypes[index] = blockType
                    if blockType == "tool_use" {
                        let toolId = block["id"] as? String ?? ""
                        let toolName = block["name"] as? String ?? ""
                        toolBlocks[index] = (toolUseId: toolId, toolName: toolName, partialJSON: "")
                    }

                case "content_block_delta":
                    guard let index = event["index"] as? Int,
                          let delta = event["delta"] as? [String: Any] else { break }
                    let deltaType = delta["type"] as? String ?? ""
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        currentText += text
                        messages[messageIndex].text = currentText
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        toolBlocks[index]?.partialJSON += partial
                    }

                case "message_delta":
                    if let delta = event["delta"] as? [String: Any] {
                        stopReason = delta["stop_reason"] as? String ?? ""
                    }

                default: break
                }
            }

            // Finalize: build history entry and handle tool calls
            let sortedToolBlocks = toolBlocks.sorted { $0.key < $1.key }

            if let (_, toolBlock) = sortedToolBlocks.first, stopReason == "tool_use" {
                // Decode tool input
                let inputData = toolBlock.partialJSON.data(using: .utf8) ?? Data()
                guard let toolInput = decodeToolInput(toolName: toolBlock.toolName, data: inputData) else {
                    messages[messageIndex].text = currentText.isEmpty
                        ? "I couldn't parse that tool response. Try again."
                        : currentText
                    apiHistory.append(.assistantText(messages[messageIndex].text))
                    return
                }

                let readOnlyTools: Set<String> = [
                    "search_food",
                    "navigate_to_tab", "open_compound", "open_dosing_calculator",
                    "open_pinning_protocol", "open_injection_tracker", "spotlight_element"
                ]
                let isReadOnly = readOnlyTools.contains(toolBlock.toolName)
                let toolCall = PepperToolCall(
                    toolUseId: toolBlock.toolUseId,
                    toolName: toolBlock.toolName,
                    input: toolInput,
                    isReadOnly: isReadOnly
                )

                // Update history with assistantWithTool entry
                apiHistory.append(.assistantWithTool(
                    text: currentText.isEmpty ? nil : currentText,
                    toolUseId: toolBlock.toolUseId,
                    toolName: toolBlock.toolName,
                    inputData: inputData
                ))

                // Attach tool call to the assistant message for display
                messages[messageIndex].toolCall = toolCall
                messages[messageIndex].toolStatus = .pending

                if isReadOnly {
                    // Auto-execute search_food without confirmation
                    messages[messageIndex].toolStatus = .confirmed("Searching...")
                    do {
                        let result = try await executeTool(toolCall, modelContext: modelContext, userId: userId)
                        messages[messageIndex].toolStatus = .confirmed(result)
                        apiHistory.append(.toolResult(toolUseId: toolBlock.toolUseId, content: result, isError: false))
                        let sysPrompt = PepperContextBuilder.buildSystemPrompt(userId: userId, modelContext: modelContext)
                        await performStream(systemPrompt: sysPrompt, modelContext: modelContext, userId: userId)
                    } catch {
                        let errMsg = error.localizedDescription
                        messages[messageIndex].toolStatus = .failed(errMsg)
                        apiHistory.append(.toolResult(toolUseId: toolBlock.toolUseId, content: errMsg, isError: true))
                        let sysPrompt = PepperContextBuilder.buildSystemPrompt(userId: userId, modelContext: modelContext)
                        await performStream(systemPrompt: sysPrompt, modelContext: modelContext, userId: userId)
                    }
                } else {
                    // Write tool: show confirmation card
                    pendingToolCall = toolCall
                }

            } else {
                // Normal text response
                if messages[messageIndex].text.isEmpty {
                    messages[messageIndex].text = "Sorry, something went wrong. Please try again."
                }
                apiHistory.append(.assistantText(messages[messageIndex].text))
                trimHistory()
            }

        } catch {
            if messages.indices.contains(messageIndex) {
                messages[messageIndex].text = "Connection error: \(error.localizedDescription)"
            }
            // Remove the incomplete user message from history
            if case .userText = apiHistory.last {
                apiHistory.removeLast()
            }
        }
    }

    // MARK: - Tool Execution

    private func executeTool(_ call: PepperToolCall, modelContext: ModelContext, userId: String) async throws -> String {
        switch call.input {
        case .logFood(let input):
            return try logFood(input, modelContext: modelContext, userId: userId)
        case .logDose(let input):
            return try logDose(input, modelContext: modelContext, userId: userId)
        case .searchFood(let input):
            return try await searchFood(input, modelContext: modelContext)
        case .logExerciseSet(let input):
            return try logExerciseSet(input, modelContext: modelContext, userId: userId)
        case .logSideEffect(let input):
            return try logSideEffect(input, modelContext: modelContext, userId: userId)
        case .createWorkoutRoutine(let input):
            return try createWorkoutRoutine(input, modelContext: modelContext, userId: userId)
        case .navigateTab(let input):
            return navigateTab(input)
        case .openCompound(let input):
            return openCompound(input)
        case .openDosingCalc(let input):
            return openDosingCalc(input)
        case .openPinningProto(let input):
            return openPinningProto(input)
        case .openInjectionTracker(let input):
            return openInjectionTracker(input)
        case .spotlight(let input):
            return spotlightElement(input)
        }
    }

    // MARK: - Navigation tool handlers

    private func navigateTab(_ input: NavigateTabInput) -> String {
        guard let nav = navigation else { return "Navigation unavailable" }
        let tab: NavigationCoordinator.Tab? = {
            switch input.tab.lowercased() {
            case "today": return .today
            case "food": return .food
            case "protocol": return .protocol
            case "track": return .track
            case "research": return .research
            default: return nil
            }
        }()
        guard let t = tab else { return "Unknown tab: \(input.tab)" }
        nav.switchTab(t)
        return "Opened \(input.tab) tab"
    }

    private func openCompound(_ input: OpenCompoundInput) -> String {
        guard let nav = navigation else { return "Navigation unavailable" }
        guard let compound = CompoundCatalog.compound(named: input.compoundName)
            ?? CompoundCatalog.match(in: input.compoundName).first.flatMap({ CompoundCatalog.compound(named: $0) }) else {
            return "Couldn't find compound: \(input.compoundName)"
        }
        nav.openCompound(compound)
        return "Opened \(compound.name)"
    }

    private func openDosingCalc(_ input: OpenCompoundInput) -> String {
        guard let nav = navigation else { return "Navigation unavailable" }
        guard let compound = CompoundCatalog.compound(named: input.compoundName)
            ?? CompoundCatalog.match(in: input.compoundName).first.flatMap({ CompoundCatalog.compound(named: $0) }) else {
            return "Couldn't find compound: \(input.compoundName)"
        }
        nav.openCompound(compound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            nav.presentDosingCalculator(for: compound)
        }
        return "Opened dosing calculator for \(compound.name)"
    }

    private func openPinningProto(_ input: OpenCompoundInput) -> String {
        guard let nav = navigation else { return "Navigation unavailable" }
        guard let compound = CompoundCatalog.compound(named: input.compoundName)
            ?? CompoundCatalog.match(in: input.compoundName).first.flatMap({ CompoundCatalog.compound(named: $0) }) else {
            return "Couldn't find compound: \(input.compoundName)"
        }
        nav.openCompound(compound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            nav.presentPinningProtocol(for: compound)
        }
        return "Opened pinning protocol for \(compound.name)"
    }

    private func openInjectionTracker(_ input: OpenInjectionTrackerInput) -> String {
        guard let nav = navigation else { return "Navigation unavailable" }
        nav.presentInjectionTracker()
        return "Opened injection site tracker"
    }

    private func spotlightElement(_ input: SpotlightInput) -> String {
        guard let spotlight = spotlight else { return "Spotlight unavailable" }
        spotlight.highlight(input.anchorId)
        return "Highlighted \(input.anchorId)"
    }

    private func logFood(_ input: LogFoodInput, modelContext: ModelContext, userId: String) throws -> String {
        let log = LocalFoodLog(
            userId: userId,
            foodName: input.foodName,
            kcal: input.estimatedKcal,
            proteinG: input.proteinG,
            carbsG: input.carbsG,
            fatG: input.fatG,
            source: "manual",
            mealWindow: input.meal  // "breakfast" | "lunch" | "dinner" | "snack" — matches FoodMeal.rawValue
        )
        log.servingQty = input.qty
        log.servingUnit = input.unit
        modelContext.insert(log)
        try modelContext.save()
        return "Logged \(input.foodName) — \(input.estimatedKcal) kcal, \(Int(input.proteinG))g protein, \(Int(input.carbsG))g carbs, \(Int(input.fatG))g fat"
    }

    private func logDose(_ input: LogDoseInput, modelContext: ModelContext, userId: String) throws -> String {
        let doseInMcg: Double
        switch input.doseUnit.lowercased() {
        case "mg": doseInMcg = input.doseAmount * 1000
        case "iu": doseInMcg = input.doseAmount // Store IU as-is in the mcg field
        default: doseInMcg = input.doseAmount
        }
        let log = LocalDoseLog(
            userId: userId,
            compoundName: input.compoundName,
            doseMcg: doseInMcg,
            injectionSite: input.injectionSite ?? "",
            notes: input.notes ?? ""
        )
        modelContext.insert(log)
        try modelContext.save()
        let siteStr = input.injectionSite.flatMap { $0.isEmpty ? nil : $0 }.map { " at \($0)" } ?? ""
        return "Logged \(input.doseAmount)\(input.doseUnit) \(input.compoundName)\(siteStr)"
    }

    private func searchFood(_ input: SearchFoodInput, modelContext: ModelContext) async throws -> String {
        let service = OpenFoodFactsService(modelContext: modelContext)
        let results = try await service.search(query: input.query)
        if results.isEmpty {
            return "No results found for \"\(input.query)\""
        }
        let lines = results.prefix(5).enumerated().map { (i, item) in
            let kcal = Int(item.kcalPer100g)
            let protein = Int(item.proteinPer100g)
            let carbs = Int(item.carbsPer100g)
            let fat = Int(item.fatPer100g)
            return "\(i + 1). \(item.name) — \(kcal) kcal/100g | \(protein)g P / \(carbs)g C / \(fat)g F per 100g"
        }.joined(separator: "\n")
        return "Search results for \"\(input.query)\":\n\(lines)"
    }

    private func logExerciseSet(_ input: LogExerciseSetInput, modelContext: ModelContext, userId: String) throws -> String {
        // Find or create exercise log for today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let exerciseName = input.exerciseName
        let descriptor = FetchDescriptor<LocalExerciseLog>(
            predicate: #Predicate { log in
                log.userId == userId &&
                log.loggedAt >= startOfDay &&
                log.loggedAt < endOfDay
            }
        )
        let todayLogs = (try? modelContext.fetch(descriptor)) ?? []
        let existingLogs = todayLogs.filter { $0.exerciseName == exerciseName }
        let exerciseLog: LocalExerciseLog
        if let existing = existingLogs.first {
            exerciseLog = existing
        } else {
            exerciseLog = LocalExerciseLog(userId: userId, exerciseName: input.exerciseName, muscleGroup: input.muscleGroup)
            modelContext.insert(exerciseLog)
        }

        // Count existing sets
        let exerciseLogId = exerciseLog.id
        let setsDescriptor = FetchDescriptor<LocalWorkoutSet>(
            predicate: #Predicate { $0.exerciseLogId == exerciseLogId }
        )
        let existingSets = (try? modelContext.fetch(setsDescriptor)) ?? []
        let setNumber = existingSets.count + 1

        let workoutSet = LocalWorkoutSet(exerciseLogId: exerciseLog.id, setNumber: setNumber, reps: input.reps, weightLbs: input.weightLbs)
        modelContext.insert(workoutSet)
        try modelContext.save()

        let weightStr = input.weightLbs == 0 ? "bodyweight" : "\(input.weightLbs) lbs"
        return "Logged \(input.exerciseName) set \(setNumber): \(input.reps) reps @ \(weightStr)"
    }

    private func logSideEffect(_ input: LogSideEffectInput, modelContext: ModelContext, userId: String) throws -> String {
        let log = LocalSideEffectLog(
            userId: userId,
            symptom: input.symptom,
            severity: input.severity,
            linkedCompoundName: input.linkedCompound
        )
        modelContext.insert(log)
        try modelContext.save()
        return "Logged side effect: \(input.symptom) (severity \(input.severity)/10)\(input.linkedCompound.map { ", linked to \($0)" } ?? "")"
    }

    private func createWorkoutRoutine(_ input: CreateWorkoutRoutineInput, modelContext: ModelContext, userId: String) throws -> String {
        let routine = LocalRoutine(userId: userId, name: input.routineName)
        modelContext.insert(routine)
        for (i, ex) in input.exercises.enumerated() {
            let exercise = LocalRoutineExercise(
                routineId: routine.id,
                exerciseName: ex.exerciseName,
                muscleGroup: ex.muscleGroup,
                targetSets: ex.targetSets,
                targetReps: ex.targetReps,
                targetWeightLbs: ex.targetWeightLbs,
                order: i
            )
            modelContext.insert(exercise)
        }
        try modelContext.save()
        let summary = input.exercises.map { "\($0.exerciseName) \($0.targetSets)x\($0.targetReps)" }.joined(separator: ", ")
        return "Created routine \"\(input.routineName)\" with \(input.exercises.count) exercise\(input.exercises.count == 1 ? "" : "s"): \(summary)"
    }

    // MARK: - Tool Input Decoding

    private func decodeToolInput(toolName: String, data: Data) -> PepperToolInput? {
        let decoder = JSONDecoder()
        switch toolName {
        case "log_food_entry":
            guard let input = try? decoder.decode(LogFoodInput.self, from: data) else { return nil }
            return .logFood(input)
        case "log_dose":
            guard let input = try? decoder.decode(LogDoseInput.self, from: data) else { return nil }
            return .logDose(input)
        case "search_food":
            guard let input = try? decoder.decode(SearchFoodInput.self, from: data) else { return nil }
            return .searchFood(input)
        case "log_exercise_set":
            guard let input = try? decoder.decode(LogExerciseSetInput.self, from: data) else { return nil }
            return .logExerciseSet(input)
        case "log_side_effect":
            guard let input = try? decoder.decode(LogSideEffectInput.self, from: data) else { return nil }
            return .logSideEffect(input)
        case "create_workout_routine":
            guard let input = try? decoder.decode(CreateWorkoutRoutineInput.self, from: data) else { return nil }
            return .createWorkoutRoutine(input)
        case "navigate_to_tab":
            guard let input = try? decoder.decode(NavigateTabInput.self, from: data) else { return nil }
            return .navigateTab(input)
        case "open_compound":
            guard let input = try? decoder.decode(OpenCompoundInput.self, from: data) else { return nil }
            return .openCompound(input)
        case "open_dosing_calculator":
            guard let input = try? decoder.decode(OpenCompoundInput.self, from: data) else { return nil }
            return .openDosingCalc(input)
        case "open_pinning_protocol":
            guard let input = try? decoder.decode(OpenCompoundInput.self, from: data) else { return nil }
            return .openPinningProto(input)
        case "open_injection_tracker":
            guard let input = try? decoder.decode(OpenInjectionTrackerInput.self, from: data) else { return nil }
            return .openInjectionTracker(input)
        case "spotlight_element":
            guard let input = try? decoder.decode(SpotlightInput.self, from: data) else { return nil }
            return .spotlight(input)
        default:
            return nil
        }
    }

    // MARK: - History Management

    private func updateToolStatus(toolUseId: String, status: PepperMessage.ToolStatus) {
        for i in messages.indices {
            if messages[i].toolCall?.toolUseId == toolUseId {
                messages[i].toolStatus = status
                break
            }
        }
    }

    private func trimHistory() {
        // Walk history as logical turns (user+assistant text, or user+assistantWithTool+toolResult+assistant)
        // Drop oldest complete turns until under the limit
        var turns: [[Int]] = []
        var i = 0

        while i < apiHistory.count {
            guard case .userText = apiHistory[i] else { i += 1; continue }
            var turn = [i]
            i += 1

            if i < apiHistory.count {
                switch apiHistory[i] {
                case .assistantWithTool:
                    turn.append(i); i += 1
                    if i < apiHistory.count, case .toolResult = apiHistory[i] {
                        turn.append(i); i += 1
                        if i < apiHistory.count, case .assistantText = apiHistory[i] {
                            turn.append(i); i += 1
                        }
                    }
                case .assistantText:
                    turn.append(i); i += 1
                default:
                    break
                }
            }
            turns.append(turn)
        }

        while turns.count > maxLogicalTurns {
            let oldest = turns.removeFirst()
            // Remove in reverse order to keep indices valid
            for idx in oldest.reversed() {
                apiHistory.remove(at: idx)
            }
            // Shift remaining turn indices
            let removed = oldest.count
            turns = turns.map { turn in turn.map { $0 - removed } }
        }
    }
}
