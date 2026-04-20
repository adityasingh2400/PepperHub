import Foundation
import PostHog

enum Analytics {
    static func configure() {
        let config = PostHogConfig(apiKey: "phc_PLACEHOLDER_REPLACE_WITH_YOUR_KEY")
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }

    static func identify(userId: String) {
        PostHogSDK.shared.identify(userId)
    }

    static func reset() {
        PostHogSDK.shared.reset()
    }

    static func capture(_ event: Event, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties.isEmpty ? nil : properties)
    }

    enum Event: String {
        // Onboarding
        case onboardingStarted        = "onboarding_started"
        case onboardingStepCompleted  = "onboarding_step_completed"
        case onboardingFinished       = "onboarding_finished"
        case onboardingSkipped        = "onboarding_skipped"

        // Auth
        case signedUp                 = "signed_up"
        case signedIn                 = "signed_in"
        case signedOut                = "signed_out"

        // Core logging
        case doseLogged               = "dose_logged"
        case foodLogged               = "food_logged"
        case workoutLogged            = "workout_logged"
        case sideEffectLogged         = "side_effect_logged"

        // Protocol
        case protocolCreated          = "protocol_created"
        case protocolActivated        = "protocol_activated"
        case vialAdded                = "vial_added"

        // Pepper AI
        case pepperOpened             = "pepper_opened"
        case pepperMessageSent        = "pepper_message_sent"
        case pepperToolConfirmed      = "pepper_tool_confirmed"
        case pepperToolCancelled      = "pepper_tool_cancelled"

        // Paywall / monetization
        case paywallViewed            = "paywall_viewed"
        case subscriptionStarted      = "subscription_started"
        case subscriptionRestored     = "subscription_restored"

        // Navigation
        case tabViewed                = "tab_viewed"

        // Food scanning
        case barcodeScanStarted       = "barcode_scan_started"
        case barcodeScanSuccess       = "barcode_scan_success"
        case barcodeScanFailed        = "barcode_scan_failed"

        // Research
        case compoundViewed           = "compound_viewed"
    }
}
