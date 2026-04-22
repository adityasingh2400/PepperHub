import SwiftUI

struct OnboardingProtocolView: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Protocol")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(Color.appTextPrimary)
                Text("This unlocks your Partition Plan meal windows.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
            }
            .padding(.horizontal, 20)

            // Yes / Not yet toggle
            HStack(spacing: 12) {
                ProtocolOptionCard(
                    title: "Yes, I'm on one",
                    subtitle: "Add compounds + dose times",
                    selected: vm.hasProtocol
                ) { vm.hasProtocol = true }

                ProtocolOptionCard(
                    title: "Not yet",
                    subtitle: "Set up later in the Protocol tab",
                    selected: !vm.hasProtocol
                ) { vm.hasProtocol = false }
            }
            .padding(.horizontal, 20)

            if vm.hasProtocol {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You can add your full protocol after signup.")
                        .font(.system(size: 14))
                        .foregroundColor(Color.appTextSecondary)
                        .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color.appAccent)
                            .font(.system(size: 14))
                        Text("Go to the Protocol tab once you're in the app to add your compounds and dose times.")
                            .font(.system(size: 13))
                            .foregroundColor(Color.appTextTertiary)
                    }
                    .padding(14)
                    .background(Color.appAccentTint)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            // CTA
            VStack(spacing: 12) {
                Button(action: { vm.step = 4 }) {
                    Text("Continue →")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                }

                Button("Skip for now") { vm.step = 4 }
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}

struct ProtocolOptionCard: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(selected ? .white : Color.appTextPrimary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(selected ? Color.white.opacity(0.85) : Color.appTextTertiary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(selected ? Color.appAccent : Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.appAccent : Color.appBorder, lineWidth: 1.5)
            )
        }
    }
}
