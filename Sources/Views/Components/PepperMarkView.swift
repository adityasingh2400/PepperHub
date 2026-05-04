import SwiftUI

/// In-app “Pepper” mark for the voice assistant FABs (replaces a generic mic glyph on the primary bubble).
struct PepperMarkView: View {
    var size: CGFloat = 24
    var color: Color = .white

    var body: some View {
        Text("P")
            .font(.system(size: size * 0.92, weight: .black, design: .rounded))
            .foregroundColor(color)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
    }
}
