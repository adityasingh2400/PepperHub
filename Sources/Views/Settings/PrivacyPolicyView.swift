import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    policyHeader(title: "Privacy Policy", subtitle: "Last updated: April 18, 2026")

                    policySection(title: "Overview") {
                        policyBody("""
Pepper ("we", "our", or "the app") is a personal health tracking application for logging peptide protocols, nutrition, and workouts. This policy explains what data we collect, how we use it, and your rights over it.

We are committed to handling your health data with care. We do not sell your data. We do not share it with advertisers.
""")
                    }

                    policySection(title: "Information We Collect") {
                        VStack(alignment: .leading, spacing: 12) {
                            policySubsection("Account Information") {
                                policyBody("When you create an account: your email address and password (stored as a one-way hash). If you use Sign in with Apple, we receive only the anonymized identifier Apple provides.")
                            }
                            policySubsection("Health & Activity Data You Log") {
                                policyBody("""
The following data is entered by you and stored to your account:
• Peptide/compound protocol details (compound names, doses, injection sites)
• Dose logs (compound, dose, time, injection site, notes)
• Food logs (food name, macros, meal time)
• Workout logs (type, duration, exercise sets)
• Side effect logs (symptom, severity, linked compound)
• Body metrics entered during onboarding (height, weight, age, biological sex, goals)

This data is stored on Supabase infrastructure (supabase.com), which uses AWS data centers in the US.
""")
                            }
                            policySubsection("AI Interactions") {
                                policyBody("""
When you use the Pepper AI feature, your messages and relevant logged data are sent to Anthropic's Claude API to generate responses. This data is processed in accordance with Anthropic's privacy policy. We do not store your AI conversation history on our servers — conversations are local to your device session.

You can disable Pepper's access to your logged data at any time in Settings → Pepper AI.
""")
                            }
                            policySubsection("Usage Data") {
                                policyBody("We do not collect analytics, crash reports, or device telemetry beyond what Apple provides to all developers via App Store Connect.")
                            }
                        }
                    }

                    policySection(title: "How We Use Your Data") {
                        policyBody("""
• To provide and operate the app's core features (dose tracking, nutrition logging, AI assistant)
• To sync your data across sessions and devices via your account
• To generate your personalized nutrition plan during onboarding
• To calculate today's macro progress and dose timing
• We do not use your data for advertising, profiling, or sale to third parties
""")
                    }

                    policySection(title: "Data Storage & Security") {
                        policyBody("""
Your data is stored on Supabase's infrastructure with Row-Level Security (RLS) enforced at the database level — only your user account can read or write your records.

All data is encrypted in transit (TLS/HTTPS). Supabase encrypts data at rest.

API calls to Anthropic for the AI feature are authenticated via short-lived session tokens. Your Anthropic API key is never stored in the app — it lives only in our secure server environment.
""")
                    }

                    policySection(title: "Subscription & Payments") {
                        policyBody("""
Peptide Pro subscriptions are processed entirely by Apple via the App Store. We do not receive or store your payment card information. Subscription management is handled through RevenueCat, which receives anonymized transaction identifiers from Apple.

To cancel your subscription, use your device's Settings → Apple ID → Subscriptions.
""")
                    }

                    policySection(title: "Your Rights & Choices") {
                        policyBody("""
• Access: You can export your data by contacting us.
• Correction: You can edit or delete individual log entries within the app.
• Deletion: You can delete your account and all associated data from Settings → Account → Delete Account. This is permanent and cannot be undone.
• Pepper AI opt-out: Disable data sharing with the AI in Settings → Pepper AI.

If you are in the EU/EEA or California, you have additional rights under GDPR and CCPA respectively. Contact us to exercise them.
""")
                    }

                    policySection(title: "Children's Privacy") {
                        policyBody("Peptide is not intended for users under the age of 18. We do not knowingly collect personal information from children.")
                    }

                    policySection(title: "Changes to This Policy") {
                        policyBody("We may update this policy from time to time. We will notify you of material changes by updating the date at the top of this page. Continued use of the app after changes constitutes acceptance.")
                    }

                    policySection(title: "Contact") {
                        policyBody("Questions about this policy or your data: privacy@getpeptide.app")
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    policyHeader(title: "Terms of Service", subtitle: "Last updated: April 18, 2026")

                    policySection(title: "Agreement") {
                        policyBody("""
By downloading or using Peptide, you agree to these Terms of Service. If you do not agree, do not use the app.

These terms apply to the Peptide iOS application and any related services.
""")
                    }

                    policySection(title: "Medical Disclaimer") {
                        policyBody("""
IMPORTANT: Peptide is a personal tracking tool only. It is not a medical device and does not provide medical advice.

Nothing in this app — including dose suggestions, nutrition plans, AI responses, or any other content — constitutes medical advice, diagnosis, or treatment. Peptides and other compounds tracked in this app may be regulated substances in your jurisdiction.

Always consult a qualified healthcare professional before starting, changing, or stopping any protocol involving compounds that affect your physiology. The developers of Peptide are not medical professionals and accept no liability for health outcomes related to use of the app.

Use this app at your own risk and in compliance with the laws of your country.
""")
                    }

                    policySection(title: "Eligibility") {
                        policyBody("You must be at least 18 years old to use Peptide. By using the app you confirm you meet this requirement.")
                    }

                    policySection(title: "Your Account") {
                        policyBody("""
You are responsible for maintaining the security of your account credentials. You are responsible for all activity that occurs under your account.

Do not create accounts on behalf of others, create fake accounts, or use the app to store data belonging to another person without their consent.
""")
                    }

                    policySection(title: "Acceptable Use") {
                        policyBody("""
You agree not to:
• Use the app for any illegal purpose or in violation of any applicable law
• Attempt to reverse engineer, decompile, or extract the app's source code
• Attempt to access other users' data
• Use automated means to access the service in ways that exceed normal personal use
• Interfere with or disrupt the app's infrastructure
""")
                    }

                    policySection(title: "Subscriptions & Refunds") {
                        policyBody("""
Peptide Pro is offered as an auto-renewing subscription. Pricing and billing periods are displayed before purchase.

Subscriptions are billed through Apple and governed by Apple's standard subscription terms. Refund requests must be made to Apple — we do not process refunds directly.

Free trial periods, where offered, convert to paid subscriptions at the end of the trial unless cancelled beforehand. Cancel any time through Settings → Apple ID → Subscriptions.
""")
                    }

                    policySection(title: "Intellectual Property") {
                        policyBody("""
The Peptide app, including its design, code, brand, and content, is owned by us and protected by copyright and other intellectual property laws.

Your personal data (logs, entries, notes) belongs to you. We claim no ownership over it.
""")
                    }

                    policySection(title: "Disclaimer of Warranties") {
                        policyBody("""
THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR FREE OF HARMFUL COMPONENTS.

TO THE FULLEST EXTENT PERMITTED BY LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
""")
                    }

                    policySection(title: "Limitation of Liability") {
                        policyBody("""
TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING FROM YOUR USE OF THE APP, INCLUDING BUT NOT LIMITED TO HEALTH OUTCOMES, DATA LOSS, OR LOSS OF PROFITS.

OUR TOTAL LIABILITY TO YOU SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP IN THE 12 MONTHS PRECEDING THE CLAIM.
""")
                    }

                    policySection(title: "Termination") {
                        policyBody("""
You may stop using the app and delete your account at any time.

We reserve the right to suspend or terminate accounts that violate these terms, with or without notice.

Upon termination, your right to use the app ceases. Data deletion happens as described in the Privacy Policy.
""")
                    }

                    policySection(title: "Changes to These Terms") {
                        policyBody("We may update these terms from time to time. Material changes will be communicated by updating the date at the top of this page. Continued use after changes constitutes acceptance.")
                    }

                    policySection(title: "Contact") {
                        policyBody("Questions about these terms: legal@getpeptide.app")
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared helpers

private func policyHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 26, weight: .black))
            .foregroundColor(Color.appTextPrimary)
        Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(Color.appTextMeta)
    }
    .padding(.bottom, 4)
}

private func policySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color.appTextPrimary)
        content()
    }
}

private func policySubsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.appTextSecondary)
        content()
    }
}

private func policyBody(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 14))
        .foregroundColor(Color.appTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(3)
}
