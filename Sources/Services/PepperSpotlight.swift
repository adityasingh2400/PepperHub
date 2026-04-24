import SwiftUI

/// Drives the pulsating maroon ring Pepper draws around an on-screen element
/// when it wants to point the user at something ("here's your MOTS-C dose").
///
/// Usage:
///   1. Any view that can be pointed at: `.pepperAnchor("motsc.units")`.
///   2. Pepper tool handler calls `spotlight.highlight("motsc.units")`.
///   3. A top-level overlay (see `PepperSpotlightOverlay`) reads the anchor's
///      frame in the root coordinate space and draws the ring.
@MainActor
final class PepperSpotlight: ObservableObject {
    @Published var activeAnchorId: String?

    /// How long the ring stays up before auto-clearing.
    private var clearTask: Task<Void, Never>?

    func highlight(_ id: String, duration: TimeInterval = 4.0) {
        activeAnchorId = id
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run { self?.activeAnchorId = nil }
            }
        }
    }

    func clear() {
        clearTask?.cancel()
        activeAnchorId = nil
    }
}

/// Coordinate space name the overlay reads against. Put it on the root of
/// `MainTabView` so every descendant can resolve its frame here.
enum PepperCoordinateSpace {
    static let root = "pepper.root"
}

private struct PepperAnchorFrame: Equatable {
    let id: String
    let frame: CGRect
}

private struct PepperAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [PepperAnchorFrame] { [] }
    static func reduce(value: inout [PepperAnchorFrame], nextValue: () -> [PepperAnchorFrame]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Tag this view as a spotlight target. Pepper can later call
    /// `spotlight.highlight("<id>")` to draw a ring around it.
    func pepperAnchor(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PepperAnchorPreferenceKey.self,
                    value: [PepperAnchorFrame(id: id, frame: proxy.frame(in: .named(PepperCoordinateSpace.root)))]
                )
            }
        )
    }
}

/// Drop this on top of the root view inside the named coordinate space.
/// It collects anchor frames and draws the pulsing ring over the active one.
struct PepperSpotlightOverlay: View {
    @EnvironmentObject private var spotlight: PepperSpotlight
    @State private var anchors: [String: CGRect] = [:]
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .onPreferenceChange(PepperAnchorPreferenceKey.self) { frames in
                    var map: [String: CGRect] = [:]
                    for f in frames { map[f.id] = f.frame }
                    anchors = map
                }

            if let id = spotlight.activeAnchorId, let frame = anchors[id] {
                ring(around: frame)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: spotlight.activeAnchorId)
        .onAppear { pulse = true }
    }

    private func ring(around frame: CGRect) -> some View {
        let padding: CGFloat = 8
        let inflated = frame.insetBy(dx: -padding, dy: -padding)
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color(hex: "9f1239"), lineWidth: 3)
            .frame(width: inflated.width, height: inflated.height)
            .position(x: inflated.midX, y: inflated.midY)
            .shadow(color: Color(hex: "9f1239").opacity(0.7), radius: pulse ? 14 : 4)
            .scaleEffect(pulse ? 1.04 : 1.0)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulse
            )
    }
}
