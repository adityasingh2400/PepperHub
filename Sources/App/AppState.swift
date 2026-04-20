import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Triggered after a dose is logged — shows side effect prompt on Today tab
    @Published var recentDoseForSideEffect: LocalDoseLog? = nil
    @Published var showSideEffectSheet = false

    func doseLogged(_ dose: LocalDoseLog) {
        recentDoseForSideEffect = dose
        // Delay 30 seconds per spec
        Task {
            try? await Task.sleep(for: .seconds(30))
            showSideEffectSheet = true
        }
    }
}
