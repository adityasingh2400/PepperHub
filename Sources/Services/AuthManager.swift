import AuthenticationServices
import Supabase
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    @Published var session: Session?
    @Published var isLoading = true
    @Published var previewMode = false
    @Published var needsOnboarding = false

    private var pendingSession: Session?

    /// Supabase user id for the signed-in or just-signed-up user. Email sign-up stores
    /// the session in `pendingSession` until onboarding completes, so prefer this over
    /// `session?.user.id` anywhere that must work mid-onboarding (profile save, RevenueCat).
    var activeUserId: UUID? {
        session?.user.id ?? pendingSession?.user.id
    }

    init() {
        Task { await restoreSession() }
        listenForAuthChanges()
    }

    private func restoreSession() async {
        do {
            let s = try await supabase.auth.session
            await applySessionFromAuth(s)
        } catch {
            session = nil
            pendingSession = nil
            needsOnboarding = false
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

    /// Single place that maps “Supabase has a session” → app routing state (profile vs onboarding).
    private func applySessionFromAuth(_ s: Session) async {
        let userId = s.user.id.uuidString
        let has = await hasProfile(userId: userId)
        if has {
            pendingSession = nil
            session = s
            needsOnboarding = false
        } else {
            pendingSession = s
            session = nil
            needsOnboarding = true
        }
    }

    private func listenForAuthChanges() {
        Task {
            for await (event, s) in supabase.auth.authStateChanges {
                guard let s else { continue }
                switch event {
                case .signedIn:
                    await applySessionFromAuth(s)
                case .tokenRefreshed:
                    if let pen = pendingSession, pen.user.id == s.user.id {
                        pendingSession = s
                    } else if let cur = session, cur.user.id == s.user.id {
                        session = s
                    } else {
                        await applySessionFromAuth(s)
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

    static func displayNameFromEmail(_ email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let cleaned = local.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return "User" }
        return cleaned.capitalized
    }

    func signUp(email: String, password: String, displayName: String?) async throws {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? Self.displayNameFromEmail(email) : trimmed
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(name)]
        )
        if let s = response.session {
            await applySessionFromAuth(s)
            Analytics.capture(.signedUp, properties: ["method": "email"])
        } else {
            pendingSession = nil
            session = nil
            needsOnboarding = false
            throw NSError(
                domain: "PepperAuth",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Check your email to confirm your account, then sign in."]
            )
        }
    }

    func completeOnboarding() {
        session = pendingSession ?? session
        pendingSession = nil
        needsOnboarding = false
        Analytics.capture(.onboardingFinished)
    }

    func signIn(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
        let s = try await supabase.auth.session
        await applySessionFromAuth(s)
        Analytics.capture(.signedIn, properties: ["method": "email"])
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        let s = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
        await applySessionFromAuth(s)
        Analytics.capture(.signedIn, properties: ["method": "apple"])
    }

    func signInWithGoogle() async throws {
        let s = try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseConfiguration.authRedirectURL,
            scopes: "openid email profile"
        ) { session in
            #if !os(tvOS) && !os(watchOS)
            session.prefersEphemeralWebBrowserSession = false
            #endif
        }
        await applySessionFromAuth(s)
        Analytics.capture(.signedIn, properties: ["method": "google"])
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
