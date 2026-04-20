import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Pepper")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(Color(hex: "9f1239"))
            ProgressView()
                .tint(Color(hex: "9f1239"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "faf5f0"))
    }
}
