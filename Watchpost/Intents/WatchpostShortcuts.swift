import AppIntents

/// Zero-setup App Shortcuts: available in Siri, Spotlight, and the Shortcuts app as soon
/// as the app is installed, with no configuration by the user.
struct WatchpostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetOpenIncidentsIntent(),
            phrases: [
                "Show open incidents in \(.applicationName)",
                "What's open in \(.applicationName)",
                "Show \(\.$minimumSeverity) incidents in \(.applicationName)"
            ],
            shortTitle: "Open Incidents",
            systemImageName: "exclamationmark.shield"
        )
        AppShortcut(
            intent: LogIncidentIntent(),
            phrases: [
                "Log an incident in \(.applicationName)",
                "Report an incident with \(.applicationName)"
            ],
            shortTitle: "Log Incident",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TriageIncidentIntent(),
            phrases: [
                "Triage \(\.$incident) in \(.applicationName)",
                "Triage an incident in \(.applicationName)"
            ],
            shortTitle: "Triage",
            systemImageName: "stethoscope"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
