import AuthenticationServices
import SwiftUI

struct OnboardingCreateAccountView: View {
    @EnvironmentObject private var authManager: AuthManager

    private static func friendlySignUpError(_ error: Error) -> String {
        let ns = error as NSError
        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("unsupported provider") || lowercasedMessage.contains("provider is not enabled") {
            return "Google and Apple sign-in are not enabled in Supabase yet. Enable both providers and add pepper://auth-callback under Authentication → URL Configuration."
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "Can't reach Pepper's servers. In Xcode, set APIKeys.supabaseURL and APIKeys.supabaseAnonKey to your Supabase project (Dashboard → Settings → API), then rebuild."
            case NSURLErrorNotConnectedToInternet:
                return "You're offline. Connect to the internet and try again."
            default:
                break
            }
        }
        return message
    }

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignIn = false
    @State private var rawAppleNonce: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Pepper")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(Color.appAccent)
                    Text("Track your stack. Time your nutrition.")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextTertiary)
                }
                .padding(.top, 56)
                .padding(.bottom, 32)

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        rawAppleNonce = AppleSignInNonce.attach(to: request)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(Capsule())
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.55 : 1)

                    googleButton

                    HStack {
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        Text("or")
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextTertiary)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    VStack(spacing: 10) {
                        PTextField(placeholder: "Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        PTextField(placeholder: "Password", text: $password, isSecure: true)
                            .textContentType(.newPassword)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: signUpWithEmail) {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue with email")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Button("Already have an account? Sign in") {
                        showSignIn = true
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color.appAccent)
                    .padding(.top, 4)

                    Text("By continuing you agree to our Terms of Service and Privacy Policy.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.appTextMeta)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    #if DEBUG
                    Button {
                        authManager.enableDebugPreviewMode()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Skip auth (debug)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color.appTextTertiary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule()
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                    }
                    .padding(.top, 12)
                    #endif
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay {
            if isLoading {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .environmentObject(authManager)
        }
    }

    private var googleButton: some View {
        Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                GoogleGMark()
                    .frame(width: 21, height: 21)
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white)
            .foregroundColor(Color.appTextPrimary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.55 : 1)
    }

    private func signUpWithEmail() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signUp(email: email, password: password, displayName: nil)
            } catch {
                errorMessage = Self.friendlySignUpError(error)
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signInWithGoogle()
            } catch {
                errorMessage = Self.friendlySignUpError(error)
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = rawAppleNonce
            else {
                errorMessage = "Could not read Sign in with Apple credentials."
                rawAppleNonce = nil
                return
            }
            rawAppleNonce = nil
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await authManager.signInWithApple(idToken: idToken, rawNonce: nonce)
                } catch {
                    errorMessage = Self.friendlySignUpError(error)
                }
                isLoading = false
            }
        case .failure(let error):
            rawAppleNonce = nil
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GoogleGMark: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = size.width * 0.16
            let inset = lineWidth / 2
            let rect = CGRect(x: inset, y: inset, width: size.width - lineWidth, height: size.height - lineWidth)

            drawArc(in: &context, rect: rect, start: .degrees(-42), end: .degrees(42), color: Color(red: 0.26, green: 0.52, blue: 0.96), width: lineWidth)
            drawArc(in: &context, rect: rect, start: .degrees(42), end: .degrees(139), color: Color(red: 0.20, green: 0.66, blue: 0.33), width: lineWidth)
            drawArc(in: &context, rect: rect, start: .degrees(139), end: .degrees(205), color: Color(red: 0.98, green: 0.74, blue: 0.18), width: lineWidth)
            drawArc(in: &context, rect: rect, start: .degrees(205), end: .degrees(318), color: Color(red: 0.92, green: 0.26, blue: 0.21), width: lineWidth)

            var bar = Path()
            bar.move(to: CGPoint(x: size.width * 0.54, y: size.height * 0.50))
            bar.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.50))
            context.stroke(
                bar,
                with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square)
            )
        }
        .accessibilityHidden(true)
    }

    private func drawArc(in context: inout GraphicsContext, rect: CGRect, start: Angle, end: Angle, color: Color, width: CGFloat) {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }
}

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PTextField(placeholder: "Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                PTextField(placeholder: "Password", text: $password, isSecure: true)

                if let error = errorMessage {
                    Text(error).font(.system(size: 13)).foregroundColor(.red)
                }

                Button(action: signIn) {
                    Group {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Sign In").font(.system(size: 16, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.appAccent).foregroundColor(.white).cornerRadius(14)
                }
                .disabled(isLoading)
            }
            .padding(24)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct PTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        .font(.system(size: 15))
    }
}
