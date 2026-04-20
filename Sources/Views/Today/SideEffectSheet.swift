import SwiftUI
import SwiftData

struct SideEffectSheet: View {
    let linkedDose: LocalDoseLog?
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let symptoms = [
        "Hunger", "Fatigue", "Water Retention", "Skin Flushing",
        "Joint Pain", "Mood", "Sleep Quality", "Libido", "Nausea",
        "Headache", "Tingling", "Bloating", "Irritability", "Increased Energy"
    ]

    @State private var selectedSymptoms: Set<String> = []
    @State private var severity = 3
    @State private var notes = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How are you feeling?")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(Color.appTextPrimary)
                        if let dose = linkedDose {
                            Text("After \(dose.compoundName) · \(Int(dose.doseMcg)) mcg")
                                .font(.system(size: 13))
                                .foregroundColor(Color.appTextTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SYMPTOMS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)

                        FlowLayout(spacing: 8) {
                            ForEach(symptoms, id: \.self) { symptom in
                                SymptomChip(
                                    label: symptom,
                                    selected: selectedSymptoms.contains(symptom)
                                ) {
                                    if selectedSymptoms.contains(symptom) {
                                        selectedSymptoms.remove(symptom)
                                    } else {
                                        selectedSymptoms.insert(symptom)
                                    }
                                }
                            }
                        }
                    }

                    if !selectedSymptoms.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SEVERITY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.appTextMeta)
                                .kerning(1.2)

                            HStack(spacing: 0) {
                                ForEach(1...5, id: \.self) { i in
                                    Button(action: { severity = i }) {
                                        VStack(spacing: 4) {
                                            Text("\(i)")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(severity == i ? .white : Color.appTextSecondary)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 44)
                                                .background(severity == i ? Color.appAccent : Color.white)
                                        }
                                    }
                                    if i < 5 {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))

                            HStack {
                                Text("Mild").font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                                Spacer()
                                Text("Severe").font(.system(size: 11)).foregroundColor(Color.appTextMeta)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.appTextMeta)
                            .kerning(1.2)
                        TextField("Any additional observations...", text: $notes, axis: .vertical)
                            .lineLimit(3)
                            .padding(12)
                            .background(Color.appCard)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Side Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .foregroundColor(Color.appTextTertiary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedSymptoms.isEmpty)
                }
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        guard let userId = authManager.session?.user.id.uuidString else {
            saveError = "You must be signed in to save."
            return
        }
        var toSync: [LocalSideEffectLog] = []
        for symptom in selectedSymptoms {
            let log = LocalSideEffectLog(
                userId: userId,
                symptom: symptom,
                severity: severity,
                notes: notes,
                linkedDoseId: linkedDose?.id,
                linkedCompoundName: linkedDose?.compoundName,
                autoLinked: linkedDose != nil
            )
            ctx.insert(log)
            toSync.append(log)
        }
        try? ctx.save()
        Analytics.capture(.sideEffectLogged, properties: ["symptom_count": selectedSymptoms.count, "severity": severity])
        Task {
            for log in toSync {
                await SyncService.shared.pushSideEffect(log, context: ctx)
            }
        }
        dismiss()
    }
}

struct SymptomChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? Color.appAccent : Color.appTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.appAccentTint : Color.white)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
                )
        }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Side Effect Correlation View

struct SideEffectCorrelationView: View {
    @Query(sort: \LocalSideEffectLog.loggedAt, order: .reverse)
    private var logs: [LocalSideEffectLog]

    var correlations: [(compound: String, symptom: String, count: Int)] {
        var counts: [String: [String: Int]] = [:]
        for log in logs {
            guard let compound = log.linkedCompoundName else { continue }
            counts[compound, default: [:]][log.symptom, default: 0] += 1
        }
        return counts.flatMap { compound, symptoms in
            symptoms.map { (compound: compound, symptom: $0.key, count: $0.value) }
        }.sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            List {
                if correlations.isEmpty {
                    Text("No correlations yet. Log side effects after doses to see patterns.")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                } else {
                    ForEach(correlations, id: \.symptom) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.symptom).font(.system(size: 14, weight: .semibold))
                                Text(c.compound).font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("×\(c.count)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.appAccent)
                        }
                    }
                }
            }
            .navigationTitle("Side Effects")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
