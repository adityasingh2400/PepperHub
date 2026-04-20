import RevenueCat
import RevenueCatUI
import SwiftUI

// Full RevenueCat paywall — uses the offering configured in the RC dashboard.
// Present this modally when a Pro-gated feature is tapped.
struct ProPaywallView: View {
    @EnvironmentObject private var purchases: PurchasesManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { info in
                purchases.update(info)
                dismiss()
            }
            .onRestoreCompleted { info in
                purchases.update(info)
                dismiss()
            }
    }
}

// Inline upgrade button — use inside blurred cards or feature gates.
struct UpgradeCTAButton: View {
    @State private var showPaywall = false
    let label: String

    var body: some View {
        Button(action: { showPaywall = true }) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.appAccent)
                .cornerRadius(12)
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
    }
}

// Gate view — wraps Pro-only content with a blur + upgrade CTA.
struct ProGate<Content: View>: View {
    @EnvironmentObject private var purchases: PurchasesManager
    @ViewBuilder let content: Content

    var body: some View {
        if purchases.isPro {
            content
        } else {
            ProLockedOverlay()
        }
    }
}

private struct ProLockedOverlay: View {
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appDivider)
                .frame(height: 120)

            VStack(spacing: 10) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color.appAccent)
                UpgradeCTAButton(label: "Start 7-Day Free Trial")
            }
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
    }
}

// Locked chart placeholder — shows upgrade prompt where a Pro chart would appear.
struct LockedChartCard: View {
    let title: String
    let detail: String
    var onUnlock: (() -> Void)? = nil
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.appTextMeta)
                .kerning(1.2)

            ZStack {
                // Ghost bars
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach([0.4, 0.7, 0.5, 0.9, 0.6, 0.8, 1.0], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appDivider)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80 * h)
                    }
                }
                .frame(height: 90)
                .blur(radius: 3)

                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.appAccent)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                    Button(action: { onUnlock?() ?? { showPaywall = true }() }) {
                        Text("Unlock with Pro")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.appAccent)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .sheet(isPresented: $showPaywall) { ProPaywallView() }
    }
}

// Customer Center — lets users manage their subscription (cancel, billing issues).
// Link to this from Settings.
struct CustomerCenterLinkView: View {
    @State private var showCustomerCenter = false

    var body: some View {
        Button(action: { showCustomerCenter = true }) {
            HStack {
                Text("Manage Subscription")
                    .font(.system(size: 15))
                    .foregroundColor(Color.appTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appTextMeta)
            }
        }
        .presentCustomerCenter(isPresented: $showCustomerCenter)
    }
}
