import SwiftUI
import SwiftData

@main
struct PeptideApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var purchasesManager = PurchasesManager.shared
    @StateObject private var appState = AppState()
    @StateObject private var pepperService = PepperService()
    @StateObject private var spotlight = PepperSpotlight()

    let modelContainer: ModelContainer

    init() {
        Analytics.configure()
        PurchasesManager.shared.configure()
        NotificationScheduler.registerCategories()

        let schema = Schema([
            LocalProtocol.self,
            LocalProtocolCompound.self,
            LocalDoseLog.self,
            LocalVial.self,
            LocalFoodLog.self,
            CachedFood.self,
            LocalSideEffectLog.self,
            LocalWorkout.self,
            CachedTimingRule.self,
            CachedUserProfile.self,
            LocalExerciseLog.self,
            LocalWorkoutSet.self,
            LocalRoutine.self,
            LocalRoutineExercise.self
        ])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
    }

    @AppStorage("dark_mode_enabled") private var darkModeEnabled = false

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoading {
                    SplashView()
                } else if authManager.needsOnboarding {
                    OnboardingFlowView()
                } else if authManager.session == nil && !authManager.previewMode {
                    OnboardingCreateAccountView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(authManager)
            .environmentObject(purchasesManager)
            .environmentObject(appState)
            .environmentObject(pepperService)
            .environmentObject(spotlight)
            .modelContainer(modelContainer)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .task {
                if let userId = authManager.session?.user.id.uuidString {
                    await purchasesManager.logIn(userId: userId)
                    Analytics.identify(userId: userId)
                }
            }
        }
    }
}
