import SwiftUI
import SwiftData

/// Entry hub when the user wants to add or replace their stack.
///
/// Three big choices, each beautifully contrasted so the right path for each
/// user is obvious at a glance:
///
///   1. "Import from notes"  — for people who already track their stack in Notes.
///   2. "Voice import"       — for people whose stack only lives in their head
///                              or on the labels of their vials.
///   3. "Plan a stack"       — for people building from scratch.
///
/// All three converge on `StackPreviewSheet` for the final review.
struct StackImportView: View {
    @Environment(\.dismiss) private var dismiss

    /// Pre-collected goals from onboarding (if any). Plumbed through to the
    /// "Plan a stack" flow so we don't ask the user the same thing twice.
    var prefilledGoals: Set<String> = []

    @State private var presentedSheet: ImportSheet?

    enum ImportSheet: String, Identifiable {
        case notes, voice, plan
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    optionCard(
                        title: "Import from notes",
                        subtitle: "Paste your stack from Apple Notes or anywhere — we extract everything in one tap.",
                        icon: "doc.on.clipboard.fill",
                        accent: Color.appAccent,
                        bestFor: "Best for: you already track your stack",
                        action: { presentedSheet = .notes }
                    )

                    optionCard(
                        title: "Voice import",
                        subtitle: "Hold your vials, tap the mic, read the labels. We pick out names, doses, and frequency live.",
                        icon: "mic.fill",
                        accent: Color(hex: "0f766e"),
                        bestFor: "Best for: you have vials but no list",
                        action: { presentedSheet = .voice }
                    )

                    optionCard(
                        title: "Plan a stack",
                        subtitle: "Tell us what you want from peptides. We design a starter stack from the catalog with rationale.",
                        icon: "sparkles",
                        accent: Color(hex: "7c3aed"),
                        bestFor: "Best for: starting from scratch",
                        action: { presentedSheet = .plan }
                    )

                    Text("All three paths land on a confirm screen — nothing saves until you tap **Use this stack**.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Add your stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $presentedSheet, onDismiss: {
                // If a downstream sheet (preview) saved the stack, dismiss
                // this hub too so the user lands on the new Stack view.
            }) { sheet in
                switch sheet {
                case .notes:
                    NotesImportView()
                case .voice:
                    VoiceImportView()
                case .plan:
                    PlanStackView(prefilledGoals: prefilledGoals)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How do you want to start?")
                .font(.system(size: 26, weight: .black))
                .foregroundColor(Color.appTextPrimary)
            Text("Pick the path that fits — they all end up in the same place.")
                .font(.system(size: 14))
                .foregroundColor(Color.appTextTertiary)
        }
    }

    private func optionCard(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        bestFor: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent)
                        .frame(width: 52, height: 52)
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.appTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bestFor)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.appTextMeta)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
