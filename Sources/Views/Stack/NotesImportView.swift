import SwiftUI
import UIKit

/// Paste-from-Notes import path. The user pastes (or types) their stack as
/// free-form text and we parse it on-device into editable rows.
///
/// Why we don't deep-link into Apple Notes:
///   Apple's Notes app doesn't expose a public AppIntents action for content
///   handoff. The fastest, most universal path is "Open Notes → Copy → Paste"
///   — which is one tap shorter than any wrangling we could do, and the
///   "Pull from clipboard" button below makes it a single tap from inside
///   Pepper.
struct NotesImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var detections: [StackParser.Detection] = []
    @State private var showPreview = false

    private let placeholder = """
    Paste your stack here. Examples:

    BPC-157 250 mcg daily
    Tirzepatide 5 mg weekly
    TB-500 — 5mg twice a week
    Ipamorelin 200 mcg, M/W/F

    We'll parse it into your stack automatically.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explainer

                    pasteCard

                    editorCard

                    if !detections.isEmpty {
                        livePreviewCard
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Import from notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { showPreview = true }
                        .bold()
                        .disabled(detections.isEmpty)
                }
            }
            .sheet(isPresented: $showPreview, onDismiss: { dismiss() }) {
                StackPreviewSheet(
                    initialDetections: detections,
                    sourceTitle: "From your notes"
                )
            }
            .onChange(of: text) { _, new in
                detections = StackParser.parse(new)
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste your stack from Apple Notes, a text message — anywhere.")
                .font(.system(size: 14))
                .foregroundColor(Color.appTextSecondary)
            Text("We extract the compound, dose, and frequency on-device. Nothing leaves your phone.")
                .font(.system(size: 12))
                .foregroundColor(Color.appTextTertiary)
        }
    }

    private var pasteCard: some View {
        Button {
            if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                text = pasted
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Pull from clipboard")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.appAccent, Color.appAccent.opacity(0.85)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: Color.appAccent.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Color.appTextMeta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 220)
            }
        }
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }

    private var livePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.appAccent)
                    .font(.system(size: 12, weight: .bold))
                Text("DETECTED")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.1)
                    .foregroundColor(Color.appTextMeta)
                Spacer()
                Text("\(detections.count) compound\(detections.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.appTextTertiary)
            }
            VStack(spacing: 8) {
                ForEach(detections) { d in
                    detectionPreviewRow(d)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }

    private func detectionPreviewRow(_ d: StackParser.Detection) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(d.confidence >= 1 ? Color.appAccent : Color.appAccent.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(d.compoundName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary)
            Spacer()
            HStack(spacing: 6) {
                if let dose = d.doseMcg {
                    miniBadge(text: "\(Int(dose)) mcg", color: Color.appAccent)
                } else {
                    miniBadge(text: "no dose", color: Color(hex: "92400e"))
                }
                if let freq = d.frequency {
                    miniBadge(text: prettyFreq(freq), color: Color.appTextSecondary)
                } else {
                    miniBadge(text: "no freq", color: Color(hex: "92400e"))
                }
            }
        }
    }

    private func miniBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func prettyFreq(_ token: String) -> String {
        switch token {
        case "daily":     return "daily"
        case "eod":       return "EOD"
        case "3x_weekly": return "3x/wk"
        case "2x_weekly": return "2x/wk"
        case "weekly":    return "weekly"
        case "5on_2off":  return "5on/2off"
        case "mwf":       return "MWF"
        default:          return token
        }
    }
}
