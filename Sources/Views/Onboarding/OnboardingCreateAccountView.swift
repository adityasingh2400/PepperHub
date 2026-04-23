import SwiftUI
import AuthenticationServices

struct OnboardingCreateAccountView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("Pepper")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(Color.appAccent)
                    Text("Track your stack. Time your nutrition.")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextTertiary)
                }
                .padding(.top, 56)
                .padding(.bottom, 36)

                VStack(spacing: 12) {
                    // Apple Sign-In (primary path)
                    SignInWithAppleButton(.signUp) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .cornerRadius(14)

                    // Divider
                    HStack {
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        Text("or").font(.system(size: 13)).foregroundColor(Color.appTextTertiary)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    // Email form
                    VStack(spacing: 10) {
                        PTextField(placeholder: "Full name", text: $displayName)
                        PTextField(placeholder: "Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        PTextField(placeholder: "Password", text: $password, isSecure: true)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: signUp) {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Create Account")
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
                    // Local-only bypass so we can iterate on the app without
                    // round-tripping through Supabase auth on every reinstall.
                    // Compiled out of release builds.
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
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .environmentObject(authManager)
        }
    }

    private func signUp() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authManager.signUp(email: email, password: password, displayName: displayName)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            // Supabase Apple Sign-In handled via native flow
            break
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
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
                    .textContentType(.emailAddress)
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

// Shared text field component
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
