import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pepperService: PepperService
    @EnvironmentObject private var spotlight: PepperSpotlight
    @StateObject private var nav = NavigationCoordinator()
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let userId = authManager.session?.user.id.uuidString ?? ""
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $nav.selectedTab) {
                TodayView(userId: userId)
                    .tabItem { Label(NavigationCoordinator.Tab.today.title,
                                     systemImage: NavigationCoordinator.Tab.today.systemImage) }
                    .tag(NavigationCoordinator.Tab.today)

                FoodTabView()
                    .tabItem { Label(NavigationCoordinator.Tab.food.title,
                                     systemImage: NavigationCoordinator.Tab.food.systemImage) }
                    .tag(NavigationCoordinator.Tab.food)

                ProtocolTabView(userId: userId)
                    .tabItem { Label(NavigationCoordinator.Tab.protocol.title,
                                     systemImage: NavigationCoordinator.Tab.protocol.systemImage) }
                    .tag(NavigationCoordinator.Tab.protocol)

                TrackTabView()
                    .tabItem { Label(NavigationCoordinator.Tab.track.title,
                                     systemImage: NavigationCoordinator.Tab.track.systemImage) }
                    .tag(NavigationCoordinator.Tab.track)

                ResearchListView()
                    .tabItem { Label(NavigationCoordinator.Tab.research.title,
                                     systemImage: NavigationCoordinator.Tab.research.systemImage) }
                    .tag(NavigationCoordinator.Tab.research)
            }
            .tint(Color(hex: "9f1239"))
            .task(id: authManager.session?.user.id) {
                guard let userId = authManager.session?.user.id.uuidString else { return }
                await SyncService.shared.bootstrap(userId: userId, context: ctx)
            }
            .onAppear {
                pepperService.navigation = nav
                pepperService.spotlight = spotlight
            }
            .environmentObject(nav)

            if nav.showVoiceNavigator {
                VoiceNavigatorView()
                    .environmentObject(nav)
                    .transition(.opacity)
                    .zIndex(2)
            } else {
                // Primary bubble = voice. Secondary small chat button below for AskPepper text chat.
                VStack(spacing: 10) {
                    PepperBubbleButton(onTap: { nav.presentVoiceNavigator() })
                    PepperChatButton(onTap: { nav.presentPepper() })
                }
                .padding(.trailing, 16)
                .padding(.bottom, 96)
                .environmentObject(nav)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: nav.showVoiceNavigator)
        .sheet(isPresented: $nav.showPepper) {
            AskPepperView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.appBackground)
        }
        .sheet(item: $nav.dosingCalculatorCompound) { compound in
            DosingCalculatorView(compound: compound)
        }
        .sheet(item: $nav.pinningProtocolCompound) { compound in
            PinningProtocolView(compound: compound)
        }
        .sheet(isPresented: $nav.showInjectionTracker) {
            InjectionTrackerView()
                .environmentObject(authManager)
        }
        .onChange(of: nav.showPepper) { _, opened in
            if opened { Analytics.capture(.pepperOpened) }
        }
        .coordinateSpace(name: PepperCoordinateSpace.root)
        .overlay(PepperSpotlightOverlay().allowsHitTesting(false))
    }
}

private struct PepperBubbleButton: View {
    var onTap: () -> Void

    @State private var pulsing = false
    @State private var pressed = false

    var body: some View {
        ZStack {
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

            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(pressed ? 0.91 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pressed = true }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pressed = false }
                onTap()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pulsing = true }
        }
        .accessibilityLabel("Voice assistant")
        .accessibilityHint("Tap to talk. Tap again to stop.")
    }
}

private struct PepperChatButton: View {
    var onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pressed = false }
                onTap()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.appCard)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.18), radius: pressed ? 3 : 10, y: pressed ? 1 : 4)
                    .overlay(Circle().stroke(Color.appBorder.opacity(0.8), lineWidth: 0.5))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "9f1239"))
            }
            .scaleEffect(pressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with Pepper")
    }
}
