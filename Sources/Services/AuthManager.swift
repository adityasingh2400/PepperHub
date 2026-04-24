import Supabase
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    @Published var session: Session?
    @Published var isLoading = true
    @Published var previewMode = false
    @Published var needsOnboarding = false

    private var pendingSession: Session?

    init() {
        Task { await restoreSession() }
        listenForAuthChanges()
    }

    private func restoreSession() async {
        do {
            let s = try await supabase.auth.session
            session = s
            // Check if this logged-in user has ever completed onboarding
            needsOnboarding = await !hasProfile(userId: s.user.id.uuidString)
        } catch {
            session = nil
        }
        isLoading = false
    }

    private func hasProfile(userId: String) async -> Bool {
        do {
            struct Row: Decodable { let user_id: String }
            let rows: [Row] = try await Task.detached {
                try await supabase
                    .from("users_profiles")
                    .select("user_id")
                    .eq("user_id", value: userId)
                    .limit(1)
                    .execute()
                    .value
            }.value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    private func listenForAuthChanges() {
        Task {
            for await (event, s) in supabase.auth.authStateChanges {
                switch event {
                case .signedIn, .tokenRefreshed:
                    if !needsOnboarding {
                        self.session = s
                    }
                case .signedOut:
                    self.session = nil
                    self.needsOnboarding = false
                    self.pendingSession = nil
                default:
                    break
                }
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
        pendingSession = response.session
        needsOnboarding = true
        Analytics.capture(.signedUp, properties: ["method": "email"])
    }

    func completeOnboarding() {
        session = pendingSession ?? session
        pendingSession = nil
        needsOnboarding = false
        Analytics.capture(.onboardingFinished)
    }

    func signIn(email: String, password: String) async throws {
        let response = try await supabase.auth.signIn(email: email, password: password)
        session = response
        Analytics.capture(.signedIn, properties: ["method": "email"])
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
        previewMode = false
        Analytics.capture(.signedOut)
        Analytics.reset()
    }

    #if DEBUG
    /// Local-only auth bypass for fast iteration. Sets `previewMode` so
    /// `PeptideApp` routes straight to `MainTabView` without ever hitting
    /// Supabase. Anything that reads `session?.user.id` will see nil — code
    /// paths that need a user id should fall back to `previewUserId` instead.
    /// Compiled out of release builds.
    func enableDebugPreviewMode() {
        previewMode = true
        needsOnboarding = false
        isLoading = false
        Analytics.capture(.signedIn, properties: ["method": "debug_preview"])
    }

    /// Stable per-install UUID used by sync code when running in preview mode,
    /// so SwiftData rows still get a consistent owner.
    static let previewUserId: String = {
        let key = "debug_preview_user_id"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
    #endif
}
