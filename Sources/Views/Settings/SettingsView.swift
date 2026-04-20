import SwiftUI
import Supabase

private struct PepperConsentToggleRow: View {
    @AppStorage("pepper_consent_granted") private var consentGranted = false

    var body: some View {
        Toggle(isOn: $consentGranted) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Pepper")
                    .foregroundColor(Color.appTextSecondary)
                Text("Sends your logged data to Claude API")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
            }
        }
        .tint(Color.appAccent)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var purchases: PurchasesManager
    @AppStorage("dark_mode_enabled") private var darkModeEnabled = false
    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section("Account") {
                    if let email = authManager.session?.user.email {
                        HStack {
                            Text("Email")
                                .foregroundColor(Color.appTextSecondary)
                            Spacer()
                            Text(email)
                                .font(.system(size: 14))
                                .foregroundColor(Color.appTextTertiary)
                        }
                    }

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            if isSigningOut {
                                ProgressView().tint(Color.appAccent)
                            } else {
                                Text("Sign Out")
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        if isDeletingAccount {
                            ProgressView().tint(.red)
                        } else {
                            Text("Delete Account")
                        }
                    }

                    if let err = deleteAccountError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }

                // Subscription
                Section("Subscription") {
                    HStack {
                        Text("Status")
                            .foregroundColor(Color.appTextSecondary)
                        Spacer()
                        Text(purchases.isPro ? "Pro" : "Free")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(purchases.isPro ? Color(hex: "166534") : Color.appTextTertiary)
                    }

                    if !purchases.isPro {
                        NavigationLink("Start Free Trial") {
                            ProPaywallView()
                                .navigationBarHidden(true)
                        }
                    } else {
                        CustomerCenterLinkView()
                    }
                }

                // Appearance
                Section("Appearance") {
                    Toggle(isOn: $darkModeEnabled) {
                        Text("Dark Mode")
                            .foregroundColor(Color.appTextSecondary)
                    }
                    .tint(Color.appAccent)
                }

                // Pepper AI
                Section("Pepper AI") {
                    PepperConsentToggleRow()
                }

                // App info
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundColor(Color.appTextSecondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(.system(size: 14))
                            .foregroundColor(Color.appTextTertiary)
                    }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("Terms of Service") { TermsOfServiceView() }
                }
            }
            .navigationTitle("Settings")
            .listStyle(.insetGrouped)
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your data and cannot be undone.")
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            try? await authManager.signOut()
            await purchases.logOut()
            isSigningOut = false
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        deleteAccountError = nil
        Task {
            do {
                guard let session = try? await supabase.auth.session else {
                    deleteAccountError = "Session expired. Please sign in again."
                    isDeletingAccount = false
                    return
                }
                guard let url = URL(string: "https://sgbszuimvqxzqvmgvyrn.supabase.co/functions/v1/delete-user") else {
                    isDeletingAccount = false
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    deleteAccountError = "Failed to delete account. Please try again."
                    isDeletingAccount = false
                    return
                }
                try? await authManager.signOut()
                await purchases.logOut()
            } catch {
                deleteAccountError = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }
}
