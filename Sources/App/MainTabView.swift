import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var ctx
    @State private var showPepper = false
    @State private var selectedTab = 0

    private let tabNames = ["today", "food", "protocol", "track", "research"]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "house.fill") }
                    .tag(0)

                FoodTabView()
                    .tabItem { Label("Food", systemImage: "fork.knife") }
                    .tag(1)

                ProtocolTabView()
                    .tabItem { Label("Protocol", systemImage: "drop.fill") }
                    .tag(2)

                TrackTabView()
                    .tabItem { Label("Track", systemImage: "figure.strengthtraining.traditional") }
                    .tag(3)

                ResearchListView()
                    .tabItem { Label("Research", systemImage: "books.vertical.fill") }
                    .tag(4)
            }
            .tint(Color(hex: "9f1239"))
            .task(id: authManager.session?.user.id) {
                guard let userId = authManager.session?.user.id.uuidString else { return }
                await SyncService.shared.bootstrap(userId: userId, context: ctx)
            }
            .onChange(of: selectedTab) { _, newTab in
                Analytics.capture(.tabViewed, properties: ["tab": tabNames[newTab]])
            }

            PepperBubbleButton(showPepper: $showPepper)
                .padding(.trailing, 20)
                .padding(.bottom, 90)
        }
        .sheet(isPresented: $showPepper) {
            AskPepperView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.appBackground)
        }
        .onChange(of: showPepper) { _, opened in
            if opened { Analytics.capture(.pepperOpened) }
        }
    }
}

private struct PepperBubbleButton: View {
    @Binding var showPepper: Bool
    @State private var pulsing = false
    @State private var pressed = false

    var body: some View {
        ZStack {
            // Pulse ring
            Circle()
                .fill(Color(hex: "9f1239").opacity(0.22))
                .frame(width: 56, height: 56)
                .scaleEffect(pulsing ? 1.65 : 1.0)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                    value: pulsing
                )

            Circle()
                .fill(Color(hex: "9f1239"))
                .frame(width: 56, height: 56)
                .shadow(color: Color(hex: "9f1239").opacity(0.45), radius: pressed ? 6 : 16, x: 0, y: pressed ? 2 : 6)
                .scaleEffect(pressed ? 0.91 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .scaleEffect(pressed ? 0.91 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pressed = false }
                showPepper = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pulsing = true }
        }
    }
}
