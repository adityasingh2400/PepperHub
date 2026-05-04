import Foundation

/// Builds Supabase URLs from `APIKeys` so Edge Functions and Auth share one project config.
/// The previous hard-coded host did not resolve in public DNS (NXDOMAIN), which surfaced as
/// “A server with the specified hostname could not be found” on sign-up.
enum SupabaseConfiguration {
    /// Deep link used by Supabase Auth (Google OAuth PKCE / `ASWebAuthenticationSession`).
    /// Add this exact URL under Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
    static let authRedirectURL = URL(string: "pepper://auth-callback")!

    private static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    static var projectURL: URL {
        if isRunningUnitTests {
            return URL(string: "https://peptide.tests.invalid")!
        }
        let raw = APIKeys.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host,
              host.contains("supabase.co") else {
            fatalError(
                """
                Invalid Supabase URL in APIKeys.swift.
                In Supabase → Project Settings → API, copy the Project URL into `APIKeys.supabaseURL`
                and the anon public key into `APIKeys.supabaseAnonKey` (see APIKeys.swift.example).
                """
            )
        }
        return url
    }

    static var anonKey: String {
        if isRunningUnitTests {
            return "unit-test-anon-key"
        }
        let k = APIKeys.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else {
            fatalError("Set APIKeys.supabaseAnonKey in Sources/Supporting/APIKeys.swift (see APIKeys.swift.example).")
        }
        return k
    }

    /// `https://<ref>.supabase.co/functions/v1/<name>`
    static func edgeFunctionURL(name: String) -> URL {
        var base = projectURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/functions/v1/\(name)") else {
            fatalError("Could not build Edge Function URL for \(name).")
        }
        return url
    }
}
