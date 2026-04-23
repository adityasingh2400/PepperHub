import SwiftUI
import SwiftData
import UIKit

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
                        subtitle: "Paste your stack — we'll auto-detect it.",
                        iconStyle: .notes,
                        accent: Color(hex: "f59e0b"),       // warm Notes yellow
                        bestFor: "Best for: you already wrote it down",
                        action: { presentedSheet = .notes }
                    )

                    optionCard(
                        title: "Voice import",
                        subtitle: "Tap the mic. Read your labels.",
                        iconStyle: .symbol("mic.fill"),
                        accent: Color(hex: "c2410c"),       // rust / burnt orange
                        bestFor: "Best for: you have vials in hand",
                        action: { presentedSheet = .voice }
                    )

                    optionCard(
                        title: "Plan a stack",
                        subtitle: "Tell us your goals. We'll design one for you.",
                        iconStyle: .symbol("sparkles"),
                        accent: Color(hex: "166534"),       // pine / growth green
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

    /// Icon options for the option card. `notes` paints a tiny mock of the
    /// Apple Notes app icon (cream/yellow paper with horizontal lines) so the
    /// "Import from notes" option *looks* like Notes, not just a coloured tile.
    enum IconStyle {
        case symbol(String)
        case notes
    }

    private func optionCard(
        title: String,
        subtitle: String,
        iconStyle: IconStyle,
        accent: Color,
        bestFor: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                iconTile(style: iconStyle, accent: accent)

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

    @ViewBuilder
    private func iconTile(style: IconStyle, accent: Color) -> some View {
        switch style {
        case .symbol(let name):
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent)
                    .frame(width: 52, height: 52)
                    .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
                Image(systemName: name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
        case .notes:
            // Mini "Notes paper" — yellow header strip + lined cream body.
            // Hits the Apple Notes brand recognition without ripping the
            // exact glyph (which would be a trademark issue).
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "fdfaf2"))
                    .frame(width: 52, height: 52)
                    .shadow(color: Color(hex: "f59e0b").opacity(0.35), radius: 10, y: 4)

                // Yellow header strip (the iconic Notes signal)
                RoundedCornerShape(corners: [.topLeft, .topRight], radius: 14)
                    .fill(accent)
                    .frame(width: 52, height: 12)

                // Lined body
                VStack(spacing: 4) {
                    Spacer().frame(height: 16)
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(Color(hex: "9ca3af").opacity(0.55))
                            .frame(width: i == 2 ? 24 : 34, height: 1.5)
                    }
                    Spacer()
                }
                .frame(width: 52, height: 52)
            }
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "f59e0b").opacity(0.35), lineWidth: 0.5)
            )
        }
    }
}

/// Per-corner rounded rectangle so we can round just the top of the Notes
/// "yellow strip" without rounding its bottom edge.
private struct RoundedCornerShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
