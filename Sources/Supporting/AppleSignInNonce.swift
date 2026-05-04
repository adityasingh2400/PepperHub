import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum AppleSignInNonce {
    /// Attaches a SHA-256–hashed nonce to the Apple request; returns the **raw** nonce to pass to Supabase.
    @discardableResult
    static func attach(to request: ASAuthorizationAppleIDRequest) -> String {
        let raw = randomRawNonce()
        request.nonce = sha256Hex(raw)
        request.requestedScopes = [.email]
        return raw
    }

    private static func randomRawNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
