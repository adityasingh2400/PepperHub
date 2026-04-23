import SwiftUI
import SwiftData
import UIKit

/// Entry hub when the user wants to add or replace their stack.
///
/// Two paths, both universal:
///   1. **Import from notes** — paste a list, we auto-detect.
///   2. **Voice import** — say what you have *or* what you want. The voice
///      flow is dual-mode: if you mention compounds, we parse them; if you
///      mention goals, we recommend a stack from the catalog.
///
/// We deliberately *don't* surface a third "Plan a stack" path because the
/// voice flow already covers it — fewer options, more intelligence.
struct StackImportView: View {
    @Environment(\.dismiss) private var dismiss

    /// Reserved for future onboarding handoffs. Currently unused since the
    /// voice flow detects goals from speech directly.
    var prefilledGoals: Set<String> = []

    @State private var presentedSheet: ImportSheet?

    enum ImportSheet: String, Identifiable {
        case notes, voice
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    optionCard(
                        title: "Voice",
                        subtitle: "Talk about what you have **or** what you want — we'll figure out the rest.",
                        iconStyle: .symbol("mic.fill"),
                        accent: Color(hex: "c2410c"),       // rust / burnt orange
                        bestFor: "Most flexible · the smart default",
                        action: { presentedSheet = .voice }
                    )

                    optionCard(
                        title: "Notes",
                        subtitle: "Paste your stack from Notes or anywhere — we'll auto-detect it.",
                        iconStyle: .notes,
                        accent: Color(hex: "f59e0b"),       // warm Notes yellow
                        bestFor: "Best if you already wrote it down",
                        action: { presentedSheet = .notes }
                    )

                    Text("Both paths land on a confirm screen — nothing saves until you tap **Use this stack**.")
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
                // If the downstream preview sheet saved the stack, dismiss
                // this hub too so the user lands on the new Stack view.
            }) { sheet in
                switch sheet {
                case .notes: NotesImportView()
                case .voice: VoiceImportView()
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
