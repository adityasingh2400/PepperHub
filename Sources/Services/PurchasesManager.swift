import RevenueCat
import SwiftUI

@MainActor
final class PurchasesManager: ObservableObject {
    static let shared = PurchasesManager()

    @Published var isPro: Bool = false
    @Published var customerInfo: CustomerInfo?
    @Published var offerings: Offerings?

    private let entitlementID = "PepperAI Pro"

    private(set) var isLoggedIn = false

    private init() {}

    func configure() {
        Purchases.configure(withAPIKey: "test_DcgcHBObAElgyrGSupXWVfsXbEQ")
        Purchases.shared.delegate = PurchasesDelegateProxy.shared
        PurchasesDelegateProxy.shared.manager = self

        #if DEBUG
        isPro = true
        #else
        Task { await refreshCustomerInfo() }
        #endif
    }

    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            update(info)
        } catch {
            // non-blocking — cached state used
        }
    }

    func fetchOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            // non-blocking
        }
    }

    func purchase(package: Package) async throws -> CustomerInfo {
        let result = try await Purchases.shared.purchase(package: package)
        update(result.customerInfo)
        Analytics.capture(.subscriptionStarted, properties: ["product": package.storeProduct.productIdentifier])
        return result.customerInfo
    }

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        update(info)
        Analytics.capture(.subscriptionRestored)
    }

    func logIn(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            isLoggedIn = true
            update(info)
        } catch {
            // non-blocking
        }
    }

    func logOut() async {
        guard isLoggedIn else { return }
        do {
            let info = try await Purchases.shared.logOut()
            isLoggedIn = false
            update(info)
        } catch {
            // non-blocking
        }
    }

    func update(_ info: CustomerInfo) {
        customerInfo = info
        isPro = info.entitlements[entitlementID]?.isActive == true
    }
}

// MARK: - Delegate proxy

final class PurchasesDelegateProxy: NSObject, PurchasesDelegate, @unchecked Sendable {
    static let shared = PurchasesDelegateProxy()
    weak var manager: PurchasesManager?

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.manager?.update(customerInfo)
        }
    }
}
