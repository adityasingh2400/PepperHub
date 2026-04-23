import SwiftUI

/// Single source of truth for "where the user is in the app".
///
/// Drives `MainTabView`'s tab selection, lets PepperService and the voice
/// navigator deep-link into specific compounds or sheets without weaving
/// state through 6 levels of view modifiers.
///
/// Public surface:
///   - `selectedTab` — current bottom tab (0…4, see `Tab`)
///   - `openCompound(_:)` — push a compound detail when leaving the user on Research
///   - `presentDosingCalculator(for:)` — pop the calculator sheet for a compound
///   - `presentPinningProtocol(for:)` — pop the pinning sheet for a compound
///   - `presentVoiceNavigator()` — open the floating voice navigator overlay
@MainActor
final class NavigationCoordinator: ObservableObject {

    enum Tab: Int, CaseIterable {
        case today = 0
        case food = 1
        case `protocol` = 2  // Stays "protocol" internally for compat;
                              // user-facing label is "Stack" (see `title`).
        case track = 3
        case research = 4

        var systemImage: String {
            switch self {
            case .today:    return "house.fill"
            case .food:     return "fork.knife"
            case .protocol: return "drop.fill"
            case .track:    return "figure.strengthtraining.traditional"
            case .research: return "books.vertical.fill"
            }
        }

        var title: String {
            switch self {
            case .today:    return "Today"
            case .food:     return "Food"
            case .protocol: return "Stack"
            case .track:    return "Track"
            case .research: return "Research"
            }
        }
    }

    @Published var selectedTab: Tab = .today

    /// When set, the Research tab will push this compound's detail view.
    @Published var researchPushedCompound: Compound? = nil

    /// Sheet presentations driven from the voice navigator.
    @Published var dosingCalculatorCompound: Compound? = nil
    @Published var pinningProtocolCompound: Compound? = nil

    /// Voice navigator overlay visibility.
    @Published var showVoiceNavigator = false

    /// Pepper assistant visibility.
    @Published var showPepper = false

    /// Quick-log dose sheet driven by voice.
    @Published var showQuickDoseLog = false

    // MARK: - High-level actions

    func switchTab(_ tab: Tab) {
        if selectedTab != tab {
            selectedTab = tab
            Analytics.capture(.tabViewed, properties: ["tab": tab.title.lowercased()])
        }
    }

    func openCompound(_ compound: Compound) {
        switchTab(.research)
        researchPushedCompound = compound
    }

    func presentDosingCalculator(for compound: Compound) {
        dosingCalculatorCompound = compound
    }

    func presentPinningProtocol(for compound: Compound) {
        pinningProtocolCompound = compound
    }

    func presentVoiceNavigator() {
        showVoiceNavigator = true
    }

    func presentPepper() {
        showPepper = true
    }

    func presentQuickDoseLog() {
        switchTab(.today)
        showQuickDoseLog = true
    }
}
