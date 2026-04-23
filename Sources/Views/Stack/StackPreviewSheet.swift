import SwiftUI
import SwiftData

/// Final review screen that all three import paths funnel into.
///
/// Shows the parsed/recommended detections as editable rows. The user can:
///   - Tweak dose / frequency
///   - Remove a row
///   - Add a manual row (compound picker)
/// Then "Use this stack" creates a fresh `LocalProtocol` and replaces any
/// existing active one.
struct StackPreviewSheet: View {
    /// The detections to start from. Each row is editable.
    let initialDetections: [StackParser.Detection]
    /// User-friendly title shown at the top (e.g. "From your notes",
    /// "From your voice", "Recommended for you").
    let sourceTitle: String
    /// Optional rationale shown above the rows (e.g. "We picked these for
    /// recovery + GH pulse based on your goals").
    let rationale: String?

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<LocalProtocol> { $0.isActive == true })
    private var activeProtocols: [LocalProtocol]

    @State private var rows: [Row] = []
    @State private var showCompoundPicker = false
    @State private var saved = false

    init(
        initialDetections: [StackParser.Detection],
        sourceTitle: String,
        rationale: String? = nil
    ) {
        self.initialDetections = initialDetections
        self.sourceTitle = sourceTitle
        self.rationale = rationale
    }

    struct Row: Identifiable, Hashable {
        let id = UUID()
        var compoundName: String
        var doseMcg: Double
        var frequency: String
        var sourceSegment: String?
        /// True when this row was inferred (auto-filled defaults). The UI
        /// surfaces a small "review" badge so the user knows to double-check.
        var isInferred: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if rows.isEmpty {
                        emptyState
                    } else {
                        ForEach($rows) { $row in
                            rowCard(row: $row)
                        }
                    }

                    Button {
                        showCompoundPicker = true
                    } label: {
                        Label("Add another compound", systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.appAccent.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                            )
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Review your stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this stack") { save() }
                        .bold()
                        .disabled(rows.isEmpty)
                }
            }
            .sheet(isPresented: $showCompoundPicker) {
                AddCompoundManuallySheet { name, dose, freq in
                    rows.append(Row(
                        compoundName: name,
                        doseMcg: dose,
                        frequency: freq,
                        sourceSegment: nil,
                        isInferred: false
                    ))
                }
            }
            .overlay {
                if saved {
                    successOverlay
                }
            }
            .onAppear { hydrate() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sourceTitle.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.1)
                .foregroundColor(Color.appAccent)
            if let rationale {
                Text(rationale)
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextSecondary)
                    .lineSpacing(3)
            } else {
                Text("Edit anything that looks off, then tap **Use this stack** to save it.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundColor(Color.appBorder)
            Text("Nothing detected yet — add a compound below.")
                .font(.system(size: 13))
                .foregroundColor(Color.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appBorder, lineWidth: 1))
    }

    private func rowCard(row: Binding<Row>) -> some View {
        let r = row.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.compoundName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                if r.isInferred {
                    Text("Review")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "92400e"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "fef3c7")))
                }
                Spacer()
                Button {
                    rows.removeAll { $0.id == r.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.appTextMeta)
                }
                .buttonStyle(.plain)
            }

            if let segment = r.sourceSegment {
                Text("\u{201C}\(segment)\u{201D}")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.appTextMeta)
                    .italic()
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                editorTile(label: "DOSE", value: "\(Int(r.doseMcg)) mcg") {
                    Stepper("", value: row.doseMcg, in: 1...10_000, step: 25)
                        .labelsHidden()
                }
                editorTile(label: "FREQUENCY", value: frequencyLabel(r.frequency)) {
                    Picker("", selection: row.frequency) {
                        ForEach(allFrequencies, id: \.0) { token, label in
                            Text(label).tag(token)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.appAccent)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(r.isInferred ? Color(hex: "fde68a") : Color.appBorder, lineWidth: 1)
        )
    }

    private func editorTile<C: View>(
        label: String,
        value: String,
        @ViewBuilder control: () -> C
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .kerning(0.6)
                    .foregroundColor(Color.appTextMeta)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appTextPrimary)
                    .monospacedDigit()
            }
            Spacer()
            control()
        }
        .padding(10)
        .background(Color.appInputBackground)
        .cornerRadius(10)
        .frame(maxWidth: .infinity)
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Color.appAccent)
                Text("Stack saved")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                Text("\(rows.count) compound\(rows.count == 1 ? "" : "s") added")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextTertiary)
            }
            .padding(28)
            .background(Color.appCard)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
        }
        .transition(.opacity)
    }

    // MARK: - Save

    private func hydrate() {
        rows = initialDetections.map {
            Row(
                compoundName: $0.compoundName,
                doseMcg: $0.doseMcg ?? defaultDose(for: $0.compoundName),
                frequency: $0.frequency ?? defaultFrequency(for: $0.compoundName),
                sourceSegment: $0.sourceSegment.isEmpty ? nil : $0.sourceSegment,
                isInferred: $0.doseMcg == nil || $0.frequency == nil
            )
        }
    }

    private func defaultDose(for name: String) -> Double {
        if let c = CompoundCatalog.compound(named: name) {
            if let low = c.dosingRangeLowMcg, let high = c.dosingRangeHighMcg {
                return ((low + high) / 2).rounded()
            }
        }
        return 100
    }

    private func defaultFrequency(for name: String) -> String {
        CompoundCatalog.compound(named: name)?.dosingFrequency ?? "daily"
    }

    private func save() {
        let userId = authManager.session?.user.id.uuidString
            ?? AuthManager.previewUserId

        // Deactivate any existing active protocol so the new one becomes the
        // single source of truth.
        activeProtocols.forEach { $0.isActive = false }

        let proto = LocalProtocol(userId: userId, name: "My Stack")
        ctx.insert(proto)
        for row in rows {
            let c = LocalProtocolCompound(
                protocolId: proto.id,
                compoundName: row.compoundName,
                doseMcg: row.doseMcg,
                frequency: row.frequency,
                doseTimes: ["08:00"]
            )
            ctx.insert(c)
            proto.compounds.append(c)
        }

        try? ctx.save()
        Analytics.capture(.protocolCreated, properties: [
            "compounds_count": rows.count,
            "source": sourceTitle
        ])

        let tz = TimeZone.current
        let cs = proto.compounds
        let p = proto
        Task {
            await NotificationScheduler.reschedule(compounds: cs, timezone: tz)
            await SyncService.shared.pushProtocol(p, userId: userId)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }

    // MARK: - Constants

    private let allFrequencies: [(String, String)] = [
        ("daily",     "Daily"),
        ("eod",       "Every other day"),
        ("3x_weekly", "3x / week"),
        ("2x_weekly", "2x / week"),
        ("weekly",    "Weekly"),
        ("5on_2off",  "5 on / 2 off"),
        ("mwf",       "M / W / F"),
    ]

    private func frequencyLabel(_ token: String) -> String {
        allFrequencies.first(where: { $0.0 == token })?.1 ?? token
    }
}

// MARK: - Manual add sheet (compound picker + dose + freq)

private struct AddCompoundManuallySheet: View {
    let onAdd: (_ name: String, _ doseMcg: Double, _ freq: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var doseMcg: Double = 100
    @State private var frequency: String = "daily"

    private var pickedName: String? { selected.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CompoundPickerView(selected: $selected)
                    .frame(maxHeight: .infinity)

                if let _ = pickedName {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Dose")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.appTextSecondary)
                            Spacer()
                            Stepper(value: $doseMcg, in: 1...10_000, step: 25) {
                                Text("\(Int(doseMcg)) mcg")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .labelsHidden()
                            Text("\(Int(doseMcg)) mcg")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        Picker("Frequency", selection: $frequency) {
                            Text("Daily").tag("daily")
                            Text("EOD").tag("eod")
                            Text("3x/week").tag("3x_weekly")
                            Text("2x/week").tag("2x_weekly")
                            Text("Weekly").tag("weekly")
                            Text("M/W/F").tag("mwf")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(16)
                    .background(Color.appCard)
                }
            }
            .navigationTitle("Add compound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let name = pickedName {
                            onAdd(name, doseMcg, frequency)
                            dismiss()
                        }
                    }
                    .disabled(pickedName == nil)
                }
            }
        }
    }
}
