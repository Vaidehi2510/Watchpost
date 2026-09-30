import SwiftData
import SwiftUI

@main
struct WatchpostApp: App {
    @State private var navigation = NavigationModel.shared

    init() {
        // Seed on first launch, warm the embedding cache, then refresh Spotlight and
        // App Shortcut parameters so Siri phrases like "Triage <incident>" resolve.
        let repository = IncidentRepository.shared
        Task { await repository.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigation)
        }
        .modelContainer(AppContainer.shared)

        #if os(macOS)
        MenuBarExtra("Watchpost", systemImage: "shield.lefthalf.filled") {
            MenuBarSummaryView()
                .environment(navigation)
                .modelContainer(AppContainer.shared)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
