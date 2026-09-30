import Foundation
import SwiftData

enum AppContainer {
    /// One on-disk store shared by the UI, App Intents, and Spotlight.
    static let shared: ModelContainer = make(inMemory: false)

    static func make(inMemory: Bool) -> ModelContainer {
        let schema = Schema([Incident.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the Watchpost store: \(error)")
        }
    }
}

/// Selection state that App Intents (Open Incident, Spotlight taps) can drive.
@Observable
@MainActor
final class NavigationModel {
    static let shared = NavigationModel()
    var selectedIncidentID: UUID?
}
