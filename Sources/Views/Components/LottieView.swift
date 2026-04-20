import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .playOnce
    var animationSpeed: CGFloat = 1.0
    var onComplete: (() -> Void)? = nil

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name)
        view.loopMode = loopMode
        view.animationSpeed = animationSpeed
        view.contentMode = .scaleAspectFit
        view.play { finished in
            if finished { onComplete?() }
        }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {}
}

// Inline success burst — no Lottie file needed, pure SwiftUI
struct SuccessBurstView: View {
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var checkScale: CGFloat = 0
    @State private var checkOpacity: Double = 0
    var onComplete: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "16a34a").opacity(0.15))
                .frame(width: 80, height: 80)
                .scaleEffect(scale)
                .opacity(opacity)

            Circle()
                .fill(Color(hex: "16a34a"))
                .frame(width: 56, height: 56)
                .scaleEffect(checkScale)

            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(checkScale)
                .opacity(checkOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                scale = 1.2
                checkScale = 1
            }
            withAnimation(.easeIn(duration: 0.15).delay(0.1)) {
                checkOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                onComplete?()
            }
        }
    }
}
