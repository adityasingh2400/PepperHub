import SwiftUI
import SwiftData

struct TrackTabView: View {
    enum Segment: String, CaseIterable {
        case workouts = "Workouts"
        case routines = "Routines"
        case sites    = "Sites"
    }
    @State private var segment: Segment = .workouts

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Segment.allCases, id: \.self) { seg in
                        Button(action: { segment = seg }) {
                            Text(seg.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(segment == seg ? Color.appAccent : Color.appTextMeta)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(segment == seg ? Color.appAccentTint : Color.clear)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appBackground)

                Divider().overlay(Color.appBorder)

                switch segment {
                case .workouts: WorkoutDiaryView()
                case .routines: RoutinesView()
                case .sites:    InjectionSiteView()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Routines View

struct RoutinesView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx

    @Query(sort: \LocalRoutine.createdAt, order: .reverse) private var routines: [LocalRoutine]
    @Query private var routineExercises: [LocalRoutineExercise]

    @State private var showCreate = false
    @State private var editingRoutine: LocalRoutine? = nil

    func exercises(for routine: LocalRoutine) -> [LocalRoutineExercise] {
        routineExercises.filter { $0.routineId == routine.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Button(action: { showCreate = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.white)
                        Text("Create Routine").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color.appAccent)
                    .cornerRadius(14)
                }

                if routines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.clipboard").font(.system(size: 40)).foregroundColor(Color.appBorder)
                        Text("No routines yet").font(.system(size: 15, weight: .semibold)).foregroundColor(Color.appTextTertiary)
                        Text("Create a routine to quickly start a pre-built workout.").font(.system(size: 13)).foregroundColor(Color.appTextMeta).multilineTextAlignment(.center)
                    }
                    .padding(40).frame(maxWidth: .infinity).background(Color.appCard).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
                } else {
                    ForEach(routines) { routine in
                        RoutineCard(routine: routine, exercises: exercises(for: routine)) {
                            editingRoutine = routine
                        }
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showCreate) {
            CreateRoutineSheet()
                .environmentObject(authManager)
        }
        .sheet(item: $editingRoutine) { routine in
            EditRoutineSheet(routine: routine)
                .environmentObject(authManager)
        }
    }
}

struct RoutineCard: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Query private var allRoutineExercises: [LocalRoutineExercise]

    let routine: LocalRoutine
    let exercises: [LocalRoutineExercise]
    let onEdit: () -> Void

    @State private var expanded = true

    var muscleGroups: String {
        let groups = Array(Set(exercises.map { $0.muscleGroup })).sorted()
        return groups.prefix(3).joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.appAccentTint)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "list.clipboard").font(.system(size: 17)).foregroundColor(Color.appAccent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")\(muscleGroups.isEmpty ? "" : " · \(muscleGroups)")")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 14)).foregroundColor(Color.appTextMeta)
                }
                .padding(.trailing, 4)
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.appTextMeta)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if expanded && !exercises.isEmpty {
                Divider().overlay(Color.appDivider)
                ForEach(exercises) { ex in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: ex.muscleGroupColorHex).opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: ex.muscleGroupIcon).font(.system(size: 11)).foregroundColor(Color(hex: ex.muscleGroupColorHex)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.exerciseName).font(.system(size: 13, weight: .medium)).foregroundColor(Color.appTextPrimary)
                            Text("\(ex.targetSets) sets × \(ex.targetReps) reps\(ex.targetWeightLbs > 0 ? " @ \(Int(ex.targetWeightLbs)) lbs" : "")")
                                .font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if ex.id != exercises.last?.id { Divider().padding(.leading, 52) }
                }
                Divider().overlay(Color.appDivider)
                // Start button
                Button(action: { startRoutine() }) {
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Start Workout").font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(Color.appAccent)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteRoutine() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func startRoutine() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        for ex in exercises {
            let log = LocalExerciseLog(userId: userId, exerciseName: ex.exerciseName, muscleGroup: ex.muscleGroup)
            ctx.insert(log)
            for i in 1...max(1, ex.targetSets) {
                let set = LocalWorkoutSet(exerciseLogId: log.id, setNumber: i, reps: ex.targetReps, weightLbs: ex.targetWeightLbs)
                ctx.insert(set)
            }
        }
        try? ctx.save()
    }

    private func deleteRoutine() {
        let rid = routine.id
        let toDelete = allRoutineExercises.filter { $0.routineId == rid }
        toDelete.forEach { ctx.delete($0) }
        ctx.delete(routine)
        try? ctx.save()
    }
}

// MARK: - Create / Edit Routine Sheet

struct CreateRoutineSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var exercises: [LocalRoutineExercise] = []
    @State private var showExSearch = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUTINE NAME").font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)
                        TextField("e.g. Push Day, Leg Day...", text: $name)
                            .font(.system(size: 16, weight: .semibold))
                            .focused($nameFocused)
                            .padding(12)
                            .background(Color.appCard)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("EXERCISES").font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)

                        if exercises.isEmpty {
                            Text("No exercises added yet.")
                                .font(.system(size: 13)).foregroundColor(Color.appTextMeta)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appCard).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(exercises.indices, id: \.self) { i in
                                    RoutineExerciseEditRow(exercise: $exercises[i]) {
                                        exercises.remove(at: i)
                                    }
                                    if i < exercises.count - 1 { Divider().padding(.leading, 14) }
                                }
                            }
                            .background(Color.appCard).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        }

                        Button(action: { showExSearch = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").foregroundColor(Color.appAccent)
                                Text("Add Exercise").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appAccent)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appCard).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showExSearch) {
                RoutineExercisePickerSheet { def in
                    let ex = LocalRoutineExercise(
                        routineId: UUID(),
                        exerciseName: def.name,
                        muscleGroup: def.muscleGroup,
                        order: exercises.count
                    )
                    exercises.append(ex)
                }
            }
        }
        .onAppear { nameFocused = true }
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        let routine = LocalRoutine(userId: userId, name: name.trimmingCharacters(in: .whitespaces))
        ctx.insert(routine)
        for (i, var ex) in exercises.enumerated() {
            ex.routineId = routine.id
            ex.order = i
            ctx.insert(ex)
        }
        try? ctx.save()
        dismiss()
    }
}

struct EditRoutineSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let routine: LocalRoutine
    @Query private var allRoutineExercises: [LocalRoutineExercise]

    @State private var name: String
    @State private var exercises: [LocalRoutineExercise] = []
    @State private var showExSearch = false
    @State private var loaded = false

    init(routine: LocalRoutine) {
        self.routine = routine
        self._name = State(initialValue: routine.name)
    }

    var existingExercises: [LocalRoutineExercise] {
        allRoutineExercises.filter { $0.routineId == routine.id }.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUTINE NAME").font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)
                        TextField("Routine name", text: $name)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                            .background(Color.appCard).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("EXERCISES").font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)

                        if exercises.isEmpty {
                            Text("No exercises.").font(.system(size: 13)).foregroundColor(Color.appTextMeta)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appCard).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(exercises.indices, id: \.self) { i in
                                    RoutineExerciseEditRow(exercise: $exercises[i]) {
                                        exercises.remove(at: i)
                                    }
                                    if i < exercises.count - 1 { Divider().padding(.leading, 14) }
                                }
                            }
                            .background(Color.appCard).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        }

                        Button(action: { showExSearch = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").foregroundColor(Color.appAccent)
                                Text("Add Exercise").font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appAccent)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appCard).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showExSearch) {
                RoutineExercisePickerSheet { def in
                    let ex = LocalRoutineExercise(
                        routineId: routine.id,
                        exerciseName: def.name,
                        muscleGroup: def.muscleGroup,
                        order: exercises.count
                    )
                    exercises.append(ex)
                }
            }
        }
        .onAppear {
            if !loaded {
                exercises = existingExercises
                loaded = true
            }
        }
    }

    private func save() {
        routine.name = name.trimmingCharacters(in: .whitespaces)
        let old = allRoutineExercises.filter { $0.routineId == routine.id }
        old.forEach { ctx.delete($0) }
        for (i, var ex) in exercises.enumerated() {
            ex.routineId = routine.id
            ex.order = i
            ctx.insert(ex)
        }
        try? ctx.save()
        dismiss()
    }
}

struct RoutineExerciseEditRow: View {
    @Binding var exercise: LocalRoutineExercise
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: exercise.muscleGroupColorHex).opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: exercise.muscleGroupIcon).font(.system(size: 12)).foregroundColor(Color(hex: exercise.muscleGroupColorHex)))
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName).font(.system(size: 13, weight: .semibold)).foregroundColor(Color.appTextPrimary)
                HStack(spacing: 6) {
                    // Sets stepper
                    HStack(spacing: 4) {
                        Button(action: { if exercise.targetSets > 1 { exercise.targetSets -= 1 } }) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundColor(Color.appAccent)
                        }
                        Text("\(exercise.targetSets)").font(.system(size: 12, weight: .bold)).frame(minWidth: 12)
                        Button(action: { exercise.targetSets += 1 }) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundColor(Color.appAccent)
                        }
                        Text("sets").font(.system(size: 11)).foregroundColor(Color.appTextTertiary)
                    }
                    Text("×").font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                    // Reps stepper
                    HStack(spacing: 4) {
                        Button(action: { if exercise.targetReps > 1 { exercise.targetReps -= 1 } }) {
                            Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundColor(Color.appAccent)
                        }
                        Text("\(exercise.targetReps)").font(.system(size: 12, weight: .bold)).frame(minWidth: 12)
                        Button(action: { exercise.targetReps += 1 }) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundColor(Color.appAccent)
                        }
                        Text("reps").font(.system(size: 11)).foregroundColor(Color.appTextTertiary)
                    }
                }
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(Color(hex: "d1d5db"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct RoutineExercisePickerSheet: View {
    let onSelect: (ExerciseDefinition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedGroup = "All"
    @FocusState private var focused: Bool

    let groups = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio"]

    var filtered: [ExerciseDefinition] {
        let byGroup = selectedGroup == "All" ? ExerciseDatabase.all : ExerciseDatabase.all.filter { $0.muscleGroup == selectedGroup }
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return byGroup }
        return byGroup.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(Color.appTextMeta)
                    TextField("Search exercises...", text: $query).focused($focused)
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color.appTextMeta)
                        }
                    }
                }
                .padding(12).background(Color.appCard).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups, id: \.self) { g in
                            Button(action: { selectedGroup = g }) {
                                Text(g).font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(selectedGroup == g ? .white : Color.appTextSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selectedGroup == g ? Color.appAccent : Color.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedGroup == g ? Color.clear : Color.appBorder, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                Divider()

                List(filtered) { ex in
                    Button(action: { onSelect(ex); dismiss() }) {
                        HStack(spacing: 12) {
                            Circle().fill(Color(hex: ex.muscleGroupColor).opacity(0.15)).frame(width: 36, height: 36)
                                .overlay(Image(systemName: ex.muscleGroupIcon).font(.system(size: 14)).foregroundColor(Color(hex: ex.muscleGroupColor)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appTextPrimary)
                                Text("\(ex.muscleGroup) · \(ex.equipment)").font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundColor(Color.appAccent)
                        }
                    }
                    .listRowBackground(Color.white)
                }
                .listStyle(.plain)
                .background(Color.appBackground)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Pick Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Workout Diary

struct WorkoutDiaryView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx

    @Query(sort: \LocalExerciseLog.loggedAt, order: .reverse)
    private var allExerciseLogs: [LocalExerciseLog]

    @Query(sort: \LocalWorkoutSet.setNumber)
    private var allSets: [LocalWorkoutSet]

    @State private var selectedDate = Date()
    @State private var showExerciseSearch = false
    @State private var showLogWorkout = false

    var todayExerciseLogs: [LocalExerciseLog] {
        allExerciseLogs.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
    }

    var streak: Int {
        var count = 0
        var day = Calendar.current.startOfDay(for: Date())
        let activeDays = Set(allExerciseLogs.map { Calendar.current.startOfDay(for: $0.loggedAt) })
        while activeDays.contains(day) {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var thisWeekCount: Int {
        guard let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) else { return 0 }
        let days = Set(allExerciseLogs.filter { $0.loggedAt >= weekStart }.map {
            Calendar.current.startOfDay(for: $0.loggedAt)
        })
        return days.count
    }

    var thisWeekSets: Int {
        guard let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) else { return 0 }
        let weekLogIds = Set(allExerciseLogs.filter { $0.loggedAt >= weekStart }.map { $0.id })
        return allSets.filter { weekLogIds.contains($0.exerciseLogId) }.count
    }

    @Query(sort: \LocalWorkout.loggedAt, order: .reverse)
    private var allWorkoutLogs: [LocalWorkout]

    var thisWeekCaloriesBurned: Int {
        guard let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) else { return 0 }
        return allWorkoutLogs.filter { $0.loggedAt >= weekStart }.reduce(0) { $0 + $1.caloriesBurned }
    }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                HStack(spacing: 0) {
                    WorkoutStatChip(value: "\(thisWeekCount)", label: "This week", icon: "calendar")
                    Divider().frame(width: 1, height: 40).overlay(Color.appBorder)
                    WorkoutStatChip(value: "\(thisWeekSets)", label: "Sets", icon: "dumbbell.fill")
                    Divider().frame(width: 1, height: 40).overlay(Color.appBorder)
                    WorkoutStatChip(value: thisWeekCaloriesBurned > 0 ? "\(thisWeekCaloriesBurned)" : "--", label: "kcal burned", icon: "flame.fill")
                    Divider().frame(width: 1, height: 40).overlay(Color.appBorder)
                    WorkoutStatChip(value: "\(streak)", label: "Streak", icon: "bolt.fill")
                }
                .padding(.vertical, 14)
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))

                HStack(spacing: 16) {
                    Button(action: {
                        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
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

                Button(action: { showExerciseSearch = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(.white)
                        Text("Add Exercise").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color.appAccent)
                    .cornerRadius(14)
                }

                if todayExerciseLogs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dumbbell").font(.system(size: 40)).foregroundColor(Color.appBorder)
                        Text("No exercises logged").font(.system(size: 15, weight: .semibold)).foregroundColor(Color.appTextTertiary)
                        Text("Tap Add Exercise to start tracking your workout.").font(.system(size: 13)).foregroundColor(Color.appTextMeta).multilineTextAlignment(.center)
                    }
                    .padding(40).frame(maxWidth: .infinity).background(Color.appCard).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
                } else {
                    ForEach(todayExerciseLogs) { log in
                        ExerciseSectionCard(
                            exerciseLog: log,
                            sets: allSets.filter { $0.exerciseLogId == log.id }
                        )
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showExerciseSearch) {
            ExerciseSearchSheet(selectedDate: selectedDate)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showLogWorkout) {
            LogWorkoutSheet(onSave: { type, duration, notes, kcal in
                guard let uid = authManager.session?.user.id.uuidString else { return }
                let w = LocalWorkout(userId: uid, type: type, durationMinutes: duration, caloriesBurned: kcal, notes: notes)
                ctx.insert(w)
                try? ctx.save()
                Task { await SyncService.shared.pushWorkout(w, context: ctx) }
            })
        }
    }
}

// MARK: - Exercise Section Card

struct ExerciseSectionCard: View {
    @Environment(\.modelContext) private var ctx
    let exerciseLog: LocalExerciseLog
    let sets: [LocalWorkoutSet]

    @State private var showLogSheet = false

    private var def: ExerciseDefinition? {
        ExerciseDatabase.all.first { $0.name == exerciseLog.exerciseName }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: def?.muscleGroupColor ?? "6b7280").opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: def?.muscleGroupIcon ?? "figure.mixed.cardio")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: def?.muscleGroupColor ?? "6b7280"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseLog.exerciseName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text(exerciseLog.muscleGroup)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: def?.muscleGroupColor ?? "6b7280"))
                }
                Spacer()
                Button(action: { showLogSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: def?.muscleGroupColor ?? "9f1239"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !sets.isEmpty {
                Divider().overlay(Color.appDivider)
                ForEach(sets.sorted { $0.setNumber < $1.setNumber }) { set in
                    ExerciseSetRow(set: set)
                    if set.id != sets.sorted(by: { $0.setNumber < $1.setNumber }).last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
        .sheet(isPresented: $showLogSheet) {
            ExerciseLogSheet(exerciseLog: exerciseLog, existingSets: sets)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                for s in sets { ctx.delete(s) }
                ctx.delete(exerciseLog)
                try? ctx.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise Set Row

struct ExerciseSetRow: View {
    @Environment(\.modelContext) private var ctx
    let set: LocalWorkoutSet

    var body: some View {
        HStack(spacing: 0) {
            Text("Set \(set.setNumber)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextTertiary)
                .frame(width: 52, alignment: .leading)
            Text("\(set.reps) reps")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.appTextPrimary)
            Spacer()
            Text(set.weightLbs == 0 ? "Bodyweight" : "\(String(format: "%.0f", set.weightLbs)) lbs")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ctx.delete(set)
                try? ctx.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise Search Sheet

struct ExerciseSearchSheet: View {
    let selectedDate: Date
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedCategory = "All"
    @State private var selectedExercise: ExerciseDefinition? = nil
    @FocusState private var focused: Bool

    @Query(sort: \LocalExerciseLog.loggedAt, order: .reverse)
    private var recentLogs: [LocalExerciseLog]

    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio"]

    private var recentUnique: [LocalExerciseLog] {
        var seen = Set<String>()
        return recentLogs.filter { seen.insert($0.exerciseName).inserted }.prefix(6).map { $0 }
    }

    private var filteredExercises: [ExerciseDefinition] {
        var results = ExerciseDatabase.search(query)
        if selectedCategory != "All" {
            results = results.filter { $0.muscleGroup == selectedCategory }
        }
        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextMeta)
                    TextField("Search exercises...", text: $query)
                        .font(.system(size: 15))
                        .focused($focused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
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
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button(action: { selectedCategory = cat }) {
                                Text(cat)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedCategory == cat ? .white : Color.appTextSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selectedCategory == cat ? Color.appAccent : Color.white)
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedCategory == cat ? Color.clear : Color.appBorder, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Divider().overlay(Color.appBorder)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if query.isEmpty && selectedCategory == "All" && !recentUnique.isEmpty {
                            Text("RECENT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 6)

                            ForEach(recentUnique) { log in
                                if let def = ExerciseDatabase.all.first(where: { $0.name == log.exerciseName }) {
                                    exerciseRow(def)
                                    Divider().padding(.leading, 50)
                                }
                            }

                            Text("ALL EXERCISES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 6)
                        }

                        ForEach(filteredExercises) { def in
                            exerciseRow(def)
                            if def.id != filteredExercises.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }

                        if filteredExercises.isEmpty {
                            VStack(spacing: 8) {
                                Text("No exercises found")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary)
                                Text("Try a different search term or category.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.appTextTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .padding(.horizontal, 32)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .background(Color.appBackground)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedExercise) { def in
                ExerciseLogSheet(
                    preselectedExercise: def,
                    selectedDate: selectedDate
                )
                .environmentObject(authManager)
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func exerciseRow(_ def: ExerciseDefinition) -> some View {
        Button(action: { selectedExercise = def }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: def.muscleGroupColor).opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: def.muscleGroupIcon)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: def.muscleGroupColor))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("\(def.muscleGroup) · \(def.equipment)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: def.muscleGroupColor))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appCard)
    }
}

// MARK: - Exercise Log Sheet

struct ExerciseLogSheet: View {
    var preselectedExercise: ExerciseDefinition? = nil
    var exerciseLog: LocalExerciseLog? = nil
    var existingSets: [LocalWorkoutSet] = []
    var selectedDate: Date = Date()

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var reps: Int = 10
    @State private var weightText: String = ""

    private var exerciseName: String {
        exerciseLog?.exerciseName ?? preselectedExercise?.name ?? ""
    }

    private var muscleGroup: String {
        exerciseLog?.muscleGroup ?? preselectedExercise?.muscleGroup ?? ""
    }

    private var def: ExerciseDefinition? {
        ExerciseDatabase.all.first { $0.name == exerciseName }
    }

    private var currentSets: [LocalWorkoutSet] {
        if let log = exerciseLog {
            return existingSets.filter { $0.exerciseLogId == log.id }.sorted { $0.setNumber < $1.setNumber }
        }
        return []
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: def?.muscleGroupColor ?? "6b7280").opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: def?.muscleGroupIcon ?? "figure.mixed.cardio")
                                .font(.system(size: 22))
                                .foregroundColor(Color(hex: def?.muscleGroupColor ?? "6b7280"))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseName)
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(Color.appTextPrimary)
                            Text(muscleGroup)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: def?.muscleGroupColor ?? "6b7280"))
                                .cornerRadius(8)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.appCard)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))

                    if !currentSets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LOGGED SETS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                            VStack(spacing: 0) {
                                ForEach(currentSets) { set in
                                    HStack {
                                        Text("Set \(set.setNumber)")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.appTextTertiary)
                                            .frame(width: 52, alignment: .leading)
                                        Text("\(set.reps) reps")
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.appTextPrimary)
                                        Spacer()
                                        Text(set.weightLbs == 0 ? "Bodyweight" : "\(String(format: "%.0f", set.weightLbs)) lbs")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.appTextSecondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    if set.id != currentSets.last?.id {
                                        Divider().padding(.leading, 14)
                                    }
                                }
                            }
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ADD SET")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)

                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                Text("Reps")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.appTextSecondary)
                                Spacer()
                                Button(action: { if reps > 1 { reps -= 1 } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(reps > 1 ? Color.appAccent : Color(hex: "d1d5db"))
                                }
                                Text("\(reps)")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(Color.appTextPrimary)
                                    .frame(minWidth: 32, alignment: .center)
                                Button(action: { reps += 1 }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(Color.appAccent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider().overlay(Color.appDivider)

                            HStack {
                                Text("Weight (lbs)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.appTextSecondary)
                                Spacer()
                                TextField("0", text: $weightText)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color.appTextPrimary)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("lbs")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.appTextMeta)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .background(Color.appCard)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }

                    Button(action: { saveSet() }) {
                        Text("Add Set")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.appAccent)
                            .cornerRadius(14)
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Log Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .onAppear { prefillFromLastSet() }
    }

    private func prefillFromLastSet() {
        if let last = currentSets.last {
            reps = last.reps
            weightText = last.weightLbs == 0 ? "" : String(format: "%.0f", last.weightLbs)
        }
    }

    private func saveSet() {
        guard let uid = authManager.session?.user.id.uuidString else { return }
        let targetLog: LocalExerciseLog
        if let existing = exerciseLog {
            targetLog = existing
        } else if let def = preselectedExercise {
            let newLog = LocalExerciseLog(userId: uid, exerciseName: def.name, muscleGroup: def.muscleGroup)
            newLog.loggedAt = selectedDate
            ctx.insert(newLog)
            targetLog = newLog
        } else {
            return
        }
        let nextSetNumber = (currentSets.map { $0.setNumber }.max() ?? 0) + 1
        let weight = Double(weightText) ?? 0
        let set = LocalWorkoutSet(
            exerciseLogId: targetLog.id,
            setNumber: nextSetNumber,
            reps: reps,
            weightLbs: weight
        )
        ctx.insert(set)
        try? ctx.save()
        reps = reps
        weightText = weightText
    }
}

struct WorkoutStatChip: View {
    let value: String; let label: String; let icon: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(Color.appAccent)
            Text(value).font(.system(size: 18, weight: .black)).foregroundColor(Color.appTextPrimary)
            Text(label).font(.system(size: 10)).foregroundColor(Color.appTextTertiary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Injection Site Body Diagram

struct SiteStatus {
    let site: String
    let lastUsed: Date?
    let daysSince: Int?
    let lastCompound: String?
    var dotColor: Color {
        guard let d = daysSince else { return Color(hex: "16a34a") }
        switch d {
        case 0:    return Color(hex: "dc2626")
        case 1, 2: return Color(hex: "f59e0b")
        default:   return Color(hex: "16a34a")
        }
    }
}

struct InjectionSiteView: View {
    @Query(sort: \LocalDoseLog.dosedAt, order: .reverse)
    private var allDoses: [LocalDoseLog]

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx

    @State private var selectedSite: String? = nil
    @State private var showingBack = false

    private let frontSites = [
        "Left Abdomen", "Right Abdomen",
        "Left Thigh",   "Right Thigh",
        "Left Arm (SubQ)", "Right Arm (SubQ)"
    ]
    private let backSites = ["Left Glute", "Right Glute"]

    private let frontPositions: [String: CGPoint] = [
        "Left Abdomen":    CGPoint(x: 0.41, y: 0.48),
        "Right Abdomen":   CGPoint(x: 0.59, y: 0.48),
        "Left Thigh":      CGPoint(x: 0.39, y: 0.73),
        "Right Thigh":     CGPoint(x: 0.61, y: 0.73),
        "Left Arm (SubQ)": CGPoint(x: 0.21, y: 0.37),
        "Right Arm (SubQ)":CGPoint(x: 0.79, y: 0.37)
    ]
    private let backPositions: [String: CGPoint] = [
        "Left Glute":  CGPoint(x: 0.40, y: 0.57),
        "Right Glute": CGPoint(x: 0.60, y: 0.57)
    ]

    var allSites: [String] { frontSites + backSites }

    func status(for site: String) -> SiteStatus {
        let last = allDoses.first { $0.injectionSite == site }
        let days = last.map { Int(Date().timeIntervalSince($0.dosedAt) / 86400) }
        return SiteStatus(site: site, lastUsed: last?.dosedAt, daysSince: days, lastCompound: last?.compoundName)
    }

    var nextRecommended: String? {
        allSites
            .map { status(for: $0) }
            .max(by: { ($0.daysSince ?? 9999) < ($1.daysSince ?? 9999) })?.site
    }

    private let bodyW: CGFloat = 160
    private let bodyH: CGFloat = 320

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                HStack(spacing: 0) {
                    LegendDot(color: Color(hex: "16a34a"), label: "Ready (3+ days)")
                    Spacer()
                    LegendDot(color: Color(hex: "f59e0b"), label: "Rest (1-2 days)")
                    Spacer()
                    LegendDot(color: Color(hex: "dc2626"), label: "Today")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.appCard).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach([(false, "Front"), (true, "Back")], id: \.0) { isBack, label in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showingBack = isBack }
                            } label: {
                                Text(label)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(showingBack == isBack ? Color.appAccent : Color.appTextMeta)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(showingBack == isBack ? Color.appAccentTint : Color.clear)
                            }
                        }
                    }
                    .background(Color(hex: "f5f0eb"))
                    .cornerRadius(12)
                    .padding(12)

                    BodyDiagramCard(
                        label: showingBack ? "BACK" : "FRONT",
                        symbol: "figure.stand",
                        flipSymbol: showingBack,
                        sites: showingBack ? backSites : frontSites,
                        positions: showingBack ? backPositions : frontPositions,
                        bodyW: bodyW, bodyH: bodyH,
                        statusFor: status,
                        nextRecommended: nextRecommended,
                        onTap: { selectedSite = $0 }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .background(Color.appCard)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))

                VStack(spacing: 0) {
                    ForEach(Array(allSites.enumerated()), id: \.element) { idx, site in
                        let s = status(for: site)
                        SiteListRow(status: s, isNext: site == nextRecommended) {
                            selectedSite = site
                        }
                        if idx < allSites.count - 1 {
                            Divider().overlay(Color.appDivider).padding(.leading, 48)
                        }
                    }
                }
                .background(Color.appCard).cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
            }
            .padding(16)
        }
        .sheet(item: Binding(
            get: { selectedSite.map { SiteWrapper(site: $0) } },
            set: { selectedSite = $0?.site }
        )) { wrapper in
            SiteDetailSheet(site: wrapper.site)
                .environmentObject(authManager)
                .environment(\.modelContext, ctx)
        }
    }
}

struct BodyDiagramCard: View {
    let label: String
    let symbol: String
    let flipSymbol: Bool
    let sites: [String]
    let positions: [String: CGPoint]
    let bodyW: CGFloat
    let bodyH: CGFloat
    let statusFor: (String) -> SiteStatus
    let nextRecommended: String?
    let onTap: (String) -> Void

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(hex: "c8b8aa"))
                .frame(width: bodyW, height: bodyH)
                .scaleEffect(x: flipSymbol ? -1 : 1, y: 1)

            ForEach(sites, id: \.self) { site in
                if let pos = positions[site] {
                    let s = statusFor(site)
                    SiteDot(status: s, isNext: site == nextRecommended)
                        .position(x: bodyW * pos.x, y: bodyH * pos.y)
                        .onTapGesture { onTap(site) }
                }
            }
        }
        .frame(width: bodyW, height: bodyH)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct SiteWrapper: Identifiable {
    let site: String
    var id: String { site }
}

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundColor(Color.appTextTertiary)
        }
    }
}

struct SiteDot: View {
    let status: SiteStatus
    let isNext: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isNext {
                Circle()
                    .fill(status.dotColor.opacity(0.25))
                    .frame(width: pulse ? 36 : 26, height: pulse ? 36 : 26)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }
            Circle()
                .fill(status.dotColor)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: status.dotColor.opacity(0.5), radius: 4, y: 2)
        }
    }
}

struct SiteListRow: View {
    let status: SiteStatus
    let isNext: Bool
    let onTap: () -> Void

    var dayLabel: String {
        guard let d = status.daysSince else { return "Never used" }
        switch d {
        case 0: return "Used today"
        case 1: return "Yesterday"
        default: return "\(d) days ago"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle().fill(status.dotColor).frame(width: 10, height: 10).padding(.leading, 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(status.site).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appTextPrimary)
                        if isNext {
                            Text("NEXT")
                                .font(.system(size: 9, weight: .black)).foregroundColor(Color.appAccent)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.appAccentTint).cornerRadius(4)
                        }
                    }
                    if let compound = status.lastCompound {
                        Text(compound).font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                    }
                }
                Spacer()
                Text(dayLabel).font(.system(size: 12, weight: .semibold)).foregroundColor(status.dotColor).padding(.trailing, 16)
            }
            .padding(.vertical, 12)
            .background(isNext ? Color.appBackground : Color.clear)
        }
    }
}

// MARK: - Site Detail Sheet

struct SiteDetailSheet: View {
    let site: String

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LocalDoseLog.dosedAt, order: .reverse)
    private var allDoses: [LocalDoseLog]

    @Query(filter: #Predicate<LocalProtocol> { $0.isActive })
    private var activeProtos: [LocalProtocol]

    @Query private var allCompounds: [LocalProtocolCompound]

    @State private var showLogSheet = false
    @State private var showSuccess = false

    private var siteDoses: [LocalDoseLog] { allDoses.filter { $0.injectionSite == site } }
    private var recentDoses: [LocalDoseLog] { Array(siteDoses.prefix(8)) }

    private var activeCompounds: [LocalProtocolCompound] {
        guard let proto = activeProtos.first else { return [] }
        return allCompounds.filter { $0.protocolId == proto.id }
    }

    private var daysSince: Int? {
        siteDoses.first.map { Int(Date().timeIntervalSince($0.dosedAt) / 86400) }
    }

    private var statusColor: Color {
        guard let d = daysSince else { return Color(hex: "16a34a") }
        switch d {
        case 0:    return Color(hex: "dc2626")
        case 1, 2: return Color(hex: "f59e0b")
        default:   return Color(hex: "16a34a")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(statusColor.opacity(0.15)).frame(width: 56, height: 56)
                            Circle().fill(statusColor).frame(width: 20, height: 20)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site).font(.system(size: 20, weight: .black)).foregroundColor(Color.appTextPrimary)
                            if let d = daysSince {
                                Text(d == 0 ? "Used today — let it rest" : d == 1 ? "Used yesterday" : "\(d) days since last use")
                                    .font(.system(size: 13)).foregroundColor(statusColor)
                            } else {
                                Text("Never used — fresh site").font(.system(size: 13)).foregroundColor(Color(hex: "16a34a"))
                            }
                        }
                        Spacer()
                    }
                    .padding(16).background(Color.appCard).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))

                    if !activeCompounds.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LOG AT THIS SITE")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)
                            ForEach(activeCompounds) { compound in
                                Button(action: { quickLog(compound: compound) }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color.appAccentTint).frame(width: 38, height: 38)
                                            Image(systemName: "syringe.fill").font(.system(size: 14)).foregroundColor(Color.appAccent)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(compound.compoundName).font(.system(size: 14, weight: .semibold)).foregroundColor(Color.appTextPrimary)
                                            Text("\(Int(compound.doseMcg)) mcg · \(compound.frequency)").font(.system(size: 12)).foregroundColor(Color.appTextTertiary)
                                        }
                                        Spacer()
                                        Text("Log Now").font(.system(size: 13, weight: .bold)).foregroundColor(Color.appAccent)
                                    }
                                    .padding(14).background(Color.appCard).cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appAccent.opacity(0.25), lineWidth: 1))
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle").foregroundColor(Color.appTextMeta)
                            Text("Set up a protocol to enable quick logging here.")
                                .font(.system(size: 13)).foregroundColor(Color.appTextTertiary)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appCard).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }

                    if recentDoses.isEmpty {
                        Text("No doses logged at this site yet.")
                            .font(.system(size: 13)).foregroundColor(Color.appTextMeta)
                            .padding(20).frame(maxWidth: .infinity)
                            .background(Color.appCard).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HISTORY AT THIS SITE")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(Color.appTextMeta).kerning(1.2)
                            ForEach(recentDoses) { dose in
                                HStack(spacing: 12) {
                                    Circle().fill(Color.appAccentTint).frame(width: 32, height: 32)
                                        .overlay(Image(systemName: "drop.fill").font(.system(size: 12)).foregroundColor(Color.appAccent))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dose.compoundName).font(.system(size: 13, weight: .semibold)).foregroundColor(Color.appTextPrimary)
                                        Text("\(Int(dose.doseMcg)) mcg").font(.system(size: 11)).foregroundColor(Color.appTextTertiary)
                                    }
                                    Spacer()
                                    Text(dose.dosedAt.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                                }
                                .padding(12).background(Color.appCard).cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appDivider, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(site)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if showSuccess {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    SuccessBurstView {
                        showSuccess = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickLog(compound: LocalProtocolCompound) {
        guard let uid = authManager.session?.user.id.uuidString else { return }
        let log = LocalDoseLog(
            userId:        uid,
            compoundName:  compound.compoundName,
            dosedAt:       .now,
            doseMcg:       compound.doseMcg,
            injectionSite: site,
            notes:         ""
        )
        log.protocolId = compound.protocolId
        ctx.insert(log)
        try? ctx.save()
        Task { await SyncService.shared.pushDoseLog(log, context: ctx) }
        showSuccess = true
    }
}
