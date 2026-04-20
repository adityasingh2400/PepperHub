import SwiftUI
import SwiftData

struct ProtocolTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var purchases: PurchasesManager
    @Environment(\.modelContext) private var ctx

    @Query(filter: #Predicate<LocalProtocol> { $0.isActive == true })
    private var activeProtocols: [LocalProtocol]

    @Query(sort: \LocalDoseLog.dosedAt, order: .reverse)
    private var doseLogs: [LocalDoseLog]

    @Query private var vials: [LocalVial]

    @Query(sort: \LocalSideEffectLog.loggedAt, order: .reverse)
    private var sideEffects: [LocalSideEffectLog]

    @State private var segment: ProtocolSegment = .protocol_
    @State private var showAddProtocol = false
    @State private var showLogDose = false
    @State private var selectedCompound: LocalProtocolCompound?
    @State private var showAddVial = false
    @State private var showDoseHistory = false
    @State private var showLogSideEffect = false
    @State private var showSideEffectHistory = false

    enum ProtocolSegment: String, CaseIterable {
        case protocol_ = "Protocol"
        case research  = "Research"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(ProtocolSegment.allCases, id: \.self) { seg in
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

                if segment == .research {
                    ResearchInlineView()
                } else {
            ScrollView {
                VStack(spacing: 16) {
                    if activeProtocols.isEmpty {
                        emptyProtocolState
                    } else {
                        ForEach(activeProtocols) { proto in
                            ProtocolCard(
                                proto: proto,
                                onLogDose: { compound in
                                    selectedCompound = compound
                                    showLogDose = true
                                },
                                onEdit: { showAddProtocol = true }
                            )
                        }

                        if let proto = activeProtocols.first, !proto.compounds.isEmpty {
                            if purchases.isPro {
                                DoseComplianceCard(
                                    compounds: proto.compounds,
                                    doseLogs: doseLogs
                                )
                            } else {
                                LockedChartCard(
                                    title: "DOSE COMPLIANCE",
                                    detail: "Track how consistently you're hitting your doses each week."
                                )
                            }
                        }
                    }

                    // Vials section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("VIALS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                            Spacer()
                            Button(action: { showAddVial = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color.appAccent)
                                    .font(.system(size: 20))
                            }
                        }

                        if vials.isEmpty {
                            Text("No vials tracked yet. Add a vial to track inventory and use the reconstitution calculator.")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextTertiary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        } else {
                            ForEach(vials) { vial in
                                VialCard(vial: vial)
                            }
                        }
                    }

                    // Side effects section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("SIDE EFFECTS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                            Spacer()
                            if !sideEffects.isEmpty {
                                Button("See All") { showSideEffectHistory = true }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.appAccent)
                            }
                            Button(action: { showLogSideEffect = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color.appAccent)
                                    .font(.system(size: 20))
                            }
                            .padding(.leading, 4)
                        }

                        if sideEffects.isEmpty {
                            Text("No symptoms logged yet. Log anything you notice while on protocol — headaches, fatigue, water retention, etc.")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextTertiary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        } else {
                            ForEach(sideEffects.prefix(4)) { effect in
                                SideEffectLogRow(effect: effect)
                            }
                        }
                    }

                    // Dose history preview
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("RECENT DOSES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)
                            Spacer()
                            Button("See All") { showDoseHistory = true }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.appAccent)
                        }

                        if doseLogs.isEmpty {
                            Text("No doses logged yet.")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextTertiary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appCard)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                        } else {
                            ForEach(doseLogs.prefix(5)) { log in
                                DoseLogRow(log: log)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground)
                } // end else (protocol segment)
            } // end VStack
            .background(Color.appBackground)
            .navigationTitle("Protocol")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddProtocol = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddProtocol) {
                AddProtocolSheet()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showLogDose) {
                if let compound = selectedCompound {
                    LogDoseSheet(compound: compound, vials: vials)
                        .environmentObject(authManager)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showAddVial) {
                AddVialSheet()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showDoseHistory) {
                DoseHistorySheet(logs: doseLogs)
            }
            .sheet(isPresented: $showLogSideEffect) {
                SideEffectSheet(linkedDose: nil)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showSideEffectHistory) {
                SideEffectHistorySheet(effects: sideEffects)
            }
        }
    }

    private var emptyProtocolState: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.circle")
                .font(.system(size: 48))
                .foregroundColor(Color.appBorder)
            Text("No active protocol")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.appTextPrimary)
            Text("Add your peptide stack to get dose reminders and unlock your Partition Plan.")
                .font(.system(size: 14))
                .foregroundColor(Color.appTextTertiary)
                .multilineTextAlignment(.center)
            Button(action: { showAddProtocol = true }) {
                Text("Add Protocol")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.appAccent)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Protocol Card

struct ProtocolCard: View {
    let proto: LocalProtocol
    let onLogDose: (LocalProtocolCompound) -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proto.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("Active since \(proto.startDate.formatted(.dateTime.month().day()))")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                }
                Spacer()
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "166534"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "dcfce7"))
                    .cornerRadius(6)
            }
            .padding(16)

            Divider().overlay(Color.appDivider)

            if proto.compounds.isEmpty {
                Text("No compounds added yet.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextTertiary)
                    .padding(14)
            } else {
                ForEach(proto.compounds) { compound in
                    CompoundRow(compound: compound, onLogDose: { onLogDose(compound) })
                    if compound.id != proto.compounds.last?.id {
                        Divider().overlay(Color.appDivider).padding(.leading, 16)
                    }
                }
            }

            Divider().overlay(Color.appDivider)

            Button(action: onEdit) {
                Text("Edit Protocol")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct CompoundRow: View {
    let compound: LocalProtocolCompound
    let onLogDose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(compound.compoundName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                HStack(spacing: 6) {
                    Text("\(Int(compound.doseMcg)) mcg")
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                    Text("·")
                        .foregroundColor(Color.appTextMeta)
                    Text(frequencyLabel(compound.frequency))
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                    if !compound.doseTimes.isEmpty {
                        Text("·")
                            .foregroundColor(Color.appTextMeta)
                        Text(compound.doseTimes.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
            }
            Spacer()
            Button(action: onLogDose) {
                Text("Log")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.appAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.appAccentTint)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func frequencyLabel(_ freq: String) -> String {
        switch freq {
        case "daily":      return "Daily"
        case "eod":        return "EOD"
        case "3x_weekly":  return "3x/week"
        case "2x_weekly":  return "2x/week"
        case "weekly":     return "Weekly"
        case "5on_2off":   return "5 on/2 off"
        case "mwf":        return "M/W/F"
        default:           return "Custom"
        }
    }
}

// MARK: - Add Protocol Sheet

struct AddProtocolSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<LocalProtocol> { $0.isActive == true })
    private var activeProtocols: [LocalProtocol]

    @State private var name = ""
    @State private var showCompoundPicker = false
    @State private var editingProtocol: LocalProtocol?
    @State private var compounds: [CompoundDraft] = []

    struct CompoundDraft: Identifiable {
        let id = UUID()
        var name: String
        var doseMcg: Double
        var frequency: String
        var doseTimes: [String]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Protocol Name") {
                    TextField("e.g. Summer Recomp", text: $name)
                }

                Section("Compounds") {
                    ForEach($compounds) { $draft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.name).font(.system(size: 14, weight: .semibold))
                            HStack {
                                Text("\(Int(draft.doseMcg)) mcg · \(draft.frequency)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(draft.doseTimes.joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { compounds.remove(atOffsets: $0) }

                    Button(action: { showCompoundPicker = true }) {
                        Label("Add Compound", systemImage: "plus.circle.fill")
                            .foregroundColor(Color.appAccent)
                    }
                }
            }
            .navigationTitle(activeProtocols.isEmpty ? "New Protocol" : "Edit Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showCompoundPicker) {
                CompoundPickerSheet { draft in
                    compounds.append(draft)
                }
            }
            .onAppear {
                if let proto = activeProtocols.first {
                    editingProtocol = proto
                    name = proto.name
                    compounds = proto.compounds.map {
                        CompoundDraft(name: $0.compoundName, doseMcg: $0.doseMcg, frequency: $0.frequency, doseTimes: $0.doseTimes)
                    }
                }
            }
        }
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }

        // Deactivate existing
        activeProtocols.forEach { $0.isActive = false }

        let proto = editingProtocol ?? {
            let p = LocalProtocol(userId: userId, name: name)
            ctx.insert(p)
            return p
        }()
        proto.name = name
        proto.isActive = true
        // Remove old compounds if editing
        proto.compounds.forEach { ctx.delete($0) }
        proto.compounds = []

        for draft in compounds {
            let c = LocalProtocolCompound(
                protocolId: proto.id,
                compoundName: draft.name,
                doseMcg: draft.doseMcg,
                frequency: draft.frequency,
                doseTimes: draft.doseTimes
            )
            ctx.insert(c)
            proto.compounds.append(c)
        }

        try? ctx.save()

        let tz = TimeZone.current
        let cs = proto.compounds
        let uid = userId
        let p = proto
        Task {
            await NotificationScheduler.reschedule(compounds: cs, timezone: tz)
            await SyncService.shared.pushProtocol(p, userId: uid)
        }

        dismiss()
    }
}

// MARK: - Compound Picker Sheet

struct CompoundPickerSheet: View {
    let onAdd: (AddProtocolSheet.CompoundDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    let knownCompounds = [
        "Ipamorelin", "CJC-1295", "BPC-157", "TB-500", "GHK-Cu",
        "Semaglutide", "Tirzepatide", "DSIP", "Selank", "Semax",
        "GHRP-6", "GHRP-2", "MK-677", "Hexarelin", "Tesamorelin",
        "PT-141", "Epithalon", "Thymosin Alpha-1", "KPV", "LL-37"
    ]

    @State private var selectedName = "Ipamorelin"
    @State private var customName = ""
    @State private var useCustom = false
    @State private var doseMcg: Double = 100
    @State private var frequency = "daily"
    @State private var times: [String] = ["08:00"]
    @State private var showTimePicker = false
    @State private var editingTimeIndex: Int? = nil

    let frequencies = ["daily","eod","3x_weekly","2x_weekly","weekly","5on_2off","mwf"]

    var compoundName: String { useCustom ? customName : selectedName }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compound") {
                    Toggle("Custom compound", isOn: $useCustom)
                    if useCustom {
                        TextField("Compound name", text: $customName)
                    } else {
                        Picker("Compound", selection: $selectedName) {
                            ForEach(knownCompounds, id: \.self) { Text($0) }
                        }
                    }
                }

                Section("Dose") {
                    HStack {
                        Text("Dose (mcg)")
                        Spacer()
                        TextField("mcg", value: $doseMcg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag("daily")
                        Text("Every other day").tag("eod")
                        Text("3x per week").tag("3x_weekly")
                        Text("2x per week").tag("2x_weekly")
                        Text("Weekly").tag("weekly")
                        Text("5 on / 2 off").tag("5on_2off")
                        Text("Mon/Wed/Fri").tag("mwf")
                    }
                }

                Section("Dose Times") {
                    ForEach(Array(times.enumerated()), id: \.offset) { i, time in
                        HStack {
                            Text(time)
                            Spacer()
                            Button("Change") {
                                editingTimeIndex = i
                                showTimePicker = true
                            }
                            .foregroundColor(Color.appAccent)
                        }
                    }
                    .onDelete { times.remove(atOffsets: $0) }

                    Button("Add Time") {
                        times.append("08:00")
                    }
                    .foregroundColor(Color.appAccent)
                }
            }
            .navigationTitle("Add Compound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(AddProtocolSheet.CompoundDraft(
                            name: compoundName,
                            doseMcg: doseMcg,
                            frequency: frequency,
                            doseTimes: times
                        ))
                        dismiss()
                    }
                    .disabled(compoundName.isEmpty || doseMcg <= 0)
                }
            }
            .sheet(isPresented: $showTimePicker) {
                TimePickerSheet(time: times[editingTimeIndex ?? 0]) { newTime in
                    if let idx = editingTimeIndex {
                        times[idx] = newTime
                    }
                }
            }
        }
    }
}

struct TimePickerSheet: View {
    @State var time: String
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date

    init(time: String, onDone: @escaping (String) -> Void) {
        self._time = State(initialValue: time)
        self.onDone = onDone
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts.first ?? 8
        comps.minute = parts.last ?? 0
        self._selectedDate = State(initialValue: cal.date(from: comps) ?? Date())
    }

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
            .navigationTitle("Set Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let h = Calendar.current.component(.hour, from: selectedDate)
                        let m = Calendar.current.component(.minute, from: selectedDate)
                        onDone(String(format: "%02d:%02d", h, m))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Log Dose Sheet

struct LogDoseSheet: View {
    let compound: LocalProtocolCompound
    let vials: [LocalVial]

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var doseMcg: Double
    @State private var site = "Left Abdomen"
    @State private var selectedVialId: UUID? = nil
    @State private var notes = ""
    @State private var showSuccess = false

    let sites = ["Left Abdomen","Right Abdomen","Left Thigh","Right Thigh","Left Deltoid","Right Deltoid"]

    init(compound: LocalProtocolCompound, vials: [LocalVial]) {
        self.compound = compound
        self.vials = vials
        self._doseMcg = State(initialValue: compound.doseMcg)
    }

    var matchingVials: [LocalVial] {
        vials.filter { $0.compoundName == compound.compoundName && $0.unitsRemaining > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compound") {
                    HStack {
                        Text(compound.compoundName)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        HStack {
                            Text("\(Int(doseMcg)) mcg")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Stepper("", value: $doseMcg, in: 1...10000, step: 5)
                                .labelsHidden()
                        }
                    }
                }

                Section("Injection Site") {
                    Picker("Site", selection: $site) {
                        ForEach(sites, id: \.self) { Text($0) }
                    }
                }

                if !matchingVials.isEmpty {
                    Section("Vial (optional)") {
                        Picker("Vial", selection: $selectedVialId) {
                            Text("Not tracked").tag(nil as UUID?)
                            ForEach(matchingVials) { vial in
                                Text("\(vial.compoundName) — \(String(format: "%.0f", vial.unitsRemaining)) units left")
                                    .tag(Optional(vial.id))
                            }
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("Any observations...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Log Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
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

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }

        let log = LocalDoseLog(
            userId: userId,
            compoundName: compound.compoundName,
            dosedAt: .now,
            doseMcg: doseMcg,
            injectionSite: site,
            notes: notes
        )
        log.protocolId = compound.protocolId
        log.vialId = selectedVialId
        ctx.insert(log)

        // Decrement vial
        var vialToSync: LocalVial?
        if let vid = selectedVialId,
           let vial = vials.first(where: { $0.id == vid }) {
            let unitsUsed = doseMcg / vial.concentrationMcgPerUnit
            vial.unitsRemaining = max(0, vial.unitsRemaining - unitsUsed)
            vialToSync = vial
        }

        try? ctx.save()
        appState.doseLogged(log)
        Task {
            await SyncService.shared.pushDoseLog(log, context: ctx)
            if let v = vialToSync {
                await SyncService.shared.pushVial(v, context: ctx)
            }
        }
        showSuccess = true
    }
}

// MARK: - Vial Card

struct VialCard: View {
    @Environment(\.modelContext) private var ctx
    let vial: LocalVial

    var unitsPerDose: Double {
        guard vial.concentrationMcgPerUnit > 0 else { return 0 }
        return 100.0 / vial.concentrationMcgPerUnit  // units to draw for 100mcg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vial.compoundName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text("\(String(format: "%.0f", vial.totalMg))mg / \(String(format: "%.1f", vial.bacWaterMl))mL BAC water")
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                }
                Spacer()
                Text("\(String(format: "%.1f", vial.concentrationMcgPerUnit)) mcg/unit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.appAccent)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appDivider)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(vial.percentRemaining > 0.2 ? Color.appAccent : Color.orange)
                        .frame(width: geo.size.width * CGFloat(vial.percentRemaining), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(String(format: "%.0f", vial.unitsRemaining)) units remaining")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
                Spacer()
                Text("100 mcg = \(String(format: "%.1f", unitsPerDose)) units")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appDivider)
                    .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Add Vial Sheet

struct AddVialSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var compoundName = "Ipamorelin"
    @State private var useCustom = false
    @State private var customName = ""
    @State private var totalMgText = "5"
    @State private var bacWaterText = "2"

    let knownCompounds = ["Ipamorelin","CJC-1295","BPC-157","TB-500","GHK-Cu","Semaglutide","Tirzepatide","GHRP-6","GHRP-2","MK-677"]

    var name: String { useCustom ? customName : compoundName }
    var totalMg: Double { Double(totalMgText) ?? 0 }
    var bacWater: Double { Double(bacWaterText) ?? 0 }
    var concentration: Double {
        guard bacWater > 0 else { return 0 }
        return (totalMg * 1000) / (bacWater * 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compound") {
                    Toggle("Custom name", isOn: $useCustom)
                    if useCustom {
                        TextField("Name", text: $customName)
                    } else {
                        Picker("Compound", selection: $compoundName) {
                            ForEach(knownCompounds, id: \.self) { Text($0) }
                        }
                    }
                }

                Section("Reconstitution") {
                    HStack {
                        Text("Total (mg)")
                        Spacer()
                        TextField("mg", text: $totalMgText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("BAC Water (mL)")
                        Spacer()
                        TextField("mL", text: $bacWaterText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                if concentration > 0 {
                    Section("Result") {
                        HStack {
                            Text("Concentration")
                            Spacer()
                            Text("\(String(format: "%.1f", concentration)) mcg / 0.1mL")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("100 mcg dose")
                            Spacer()
                            Text("\(String(format: "%.1f", 100.0/concentration)) units")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Vial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.isEmpty || totalMg <= 0 || bacWater <= 0)
                }
            }
        }
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else { return }
        let vial = LocalVial(userId: userId, compoundName: name, totalMg: totalMg, bacWaterMl: bacWater)
        ctx.insert(vial)
        try? ctx.save()
        Task { await SyncService.shared.pushVial(vial, context: ctx) }
        dismiss()
    }
}

// MARK: - Dose Log Row

struct DoseLogRow: View {
    let log: LocalDoseLog

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.appAccentTint)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "drop.fill").font(.system(size: 14)).foregroundColor(Color.appAccent))

            VStack(alignment: .leading, spacing: 2) {
                Text(log.compoundName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text("\(Int(log.doseMcg)) mcg · \(log.injectionSite)")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
            }
            Spacer()
            Text(log.dosedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundColor(Color.appTextMeta)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Side Effect Log Row

struct SideEffectLogRow: View {
    let effect: LocalSideEffectLog

    private var severityColor: Color {
        switch effect.severity {
        case 1...3: return Color(hex: "16a34a")
        case 4...6: return Color(hex: "f59e0b")
        default:    return Color(hex: "dc2626")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(severityColor.opacity(0.12)).frame(width: 36, height: 36)
                Text("\(effect.severity)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(severityColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.symptom)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                HStack(spacing: 4) {
                    if let compound = effect.linkedCompoundName {
                        Text(compound)
                            .font(.system(size: 11))
                            .foregroundColor(Color.appAccent)
                    }
                    if effect.linkedCompoundName != nil {
                        Text("·").font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                    }
                    Text(effect.loggedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                }
            }
            Spacer()
            if !effect.notes.isEmpty {
                Image(systemName: "note.text")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextMeta)
            }
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Side Effect History Sheet

struct SideEffectHistorySheet: View {
    let effects: [LocalSideEffectLog]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    var grouped: [(String, [LocalSideEffectLog])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: effects) { e -> String in
            if cal.isDateInToday(e.loggedAt)     { return "Today" }
            if cal.isDateInYesterday(e.loggedAt) { return "Yesterday" }
            return e.loggedAt.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return dict.sorted { a, b in
            let order = ["Today", "Yesterday"]
            let ai = order.firstIndex(of: a.key)
            let bi = order.firstIndex(of: b.key)
            if let ai, let bi { return ai < bi }
            if ai != nil { return true }
            if bi != nil { return false }
            return (a.value.first?.loggedAt ?? .distantPast) > (b.value.first?.loggedAt ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { date, entries in
                    Section(date) {
                        ForEach(entries) { effect in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(effect.symptom)
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Text("Severity \(effect.severity)/10")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(effect.severity >= 7 ? Color(hex: "dc2626") : effect.severity >= 4 ? Color(hex: "f59e0b") : Color(hex: "16a34a"))
                                }
                                if let compound = effect.linkedCompoundName {
                                    Text("Linked to \(compound)")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.appAccent)
                                }
                                if !effect.notes.isEmpty {
                                    Text(effect.notes)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { ctx.delete(entries[i]) }
                            try? ctx.save()
                        }
                    }
                }
            }
            .navigationTitle("Symptom History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Dose History Sheet

struct DoseHistorySheet: View {
    let logs: [LocalDoseLog]
    @Environment(\.dismiss) private var dismiss

    var grouped: [(String, [LocalDoseLog])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: logs) { log -> String in
            if cal.isDateInToday(log.dosedAt) { return "Today" }
            if cal.isDateInYesterday(log.dosedAt) { return "Yesterday" }
            return log.dosedAt.formatted(.dateTime.month().day())
        }
        return dict.sorted { a, b in
            let order = ["Today","Yesterday"]
            let ai = order.firstIndex(of: a.key)
            let bi = order.firstIndex(of: b.key)
            if let ai, let bi { return ai < bi }
            if ai != nil { return true }
            if bi != nil { return false }
            return a.key > b.key
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { date, entries in
                    Section(date) {
                        ForEach(entries) { log in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.compoundName)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("\(Int(log.doseMcg)) mcg · \(log.injectionSite)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(log.dosedAt.formatted(.dateTime.hour().minute()))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dose History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Research Inline View

struct ResearchInlineView: View {
    @State private var compounds: [Compound] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var filtered: [Compound] {
        if searchText.isEmpty { return compounds }
        return compounds.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.benefits.joined().localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Text("Couldn't load compounds")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text(error).font(.system(size: 13)).foregroundColor(Color.appTextTertiary)
                    Button("Retry") { Task { await load() } }
                        .foregroundColor(Color.appAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { compound in
                            NavigationLink(destination: CompoundDetailView(compound: compound)) {
                                CompoundRowView(compound: compound)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(Color.appBackground)
                .searchable(text: $searchText, prompt: "Search compounds")
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result: [Compound] = try await Task.detached {
                try await supabase
                    .from("compounds")
                    .select()
                    .order("name")
                    .execute()
                    .value
            }.value
            compounds = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
