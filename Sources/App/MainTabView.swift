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
            .task(id: authManager.activeUserId?.uuidString) {
                guard let userId = authManager.activeUserId?.uuidString else { return }
                await SyncService.shared.bootstrap(userId: userId, context: ctx)
            }
            .onAppear {
                pepperService.navigation = nav
                pepperService.spotlight = spotlight
                nav.spotlight = spotlight
                // Voice nav is silent (no TTS confirmations) — the UI is
                // the feedback channel. Skip prerecorded-audio prewarm;
                // still prewarm the audio session so AskPepper's TTS (the
                // separate chat surface) has a warm start when invoked.
                PrerecordedAudioCache.shared.prewarmAudioSession()
            }
            .environmentObject(nav)

            VoiceNavigatorPrewarmView()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(0.5)

            if nav.showVoiceNavigator {
                VoiceNavigatorView()
                    .environmentObject(nav)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(2)
            } else {
                // Single floating voice button — the chat-bubble icon that
                // used to sit below was bloat. AskPepper still opens when
                // Pepper needs to surface a free-form answer (see
                // `VoiceNavigatorView.handlePepperResponseIfNeeded`), just
                // without a dedicated manual entry point.
                PepperBubbleButton(onTap: { nav.presentVoiceNavigator() })
                    .padding(.trailing, 16)
                    .padding(.bottom, 110)
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

    @State private var pressed = false

    // Idle state: light wine background. Activation swaps this view for
    // VoiceNavigatorView's PepperFaceView which handles the transition into
    // dark wine + eyes + amino-acid mouth.
    private let lightWine = Color(hex: "9f1239")

    var body: some View {
        ZStack {
            Circle()
                .fill(lightWine)
                .frame(width: 56, height: 56)
                .shadow(color: lightWine.opacity(0.45), radius: pressed ? 6 : 16, x: 0, y: pressed ? 2 : 6)
                .scaleEffect(pressed ? 0.91 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)

            PepperMarkView(size: 24, color: .white)
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
        .accessibilityLabel("Voice assistant")
        .accessibilityHint("Tap to talk. Tap again to stop.")
    }
}
