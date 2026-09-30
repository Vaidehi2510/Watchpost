import AppIntents
import Foundation
import WatchpostCore

/// "Log Incident" — create an incident from Siri, Shortcuts, or an automation.
struct LogIncidentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Incident"
    static let description: IntentDescription? = IntentDescription(
        "Records a new incident in Watchpost and returns it for use in later steps."
    )

    @Parameter(title: "Title", requestValueDialog: "What happened?")
    var incidentTitle: String

    @Parameter(title: "Details")
    var details: String?

    @Parameter(title: "Severity", default: .medium)
    var severity: SeverityOption

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$incidentTitle) as \(\.$severity)") {
            \.$details
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IncidentEntity> & ProvidesDialog {
        let incident = try IncidentRepository.shared.log(
            title: incidentTitle,
            details: details ?? "",
            severity: severity.severity,
            source: "Shortcuts"
        )
        return .result(
            value: IncidentEntity(incident),
            dialog: "Logged a \(severity.label.lowercased()) incident: \(incident.title)."
        )
    }
}

/// "Triage Incident" — returns a priority score and next step. Siri speaks the dialog;
/// the returned text can be piped into Messages, Mail, Notes, etc.
struct TriageIncidentIntent: AppIntent {
    static let title: LocalizedStringResource = "Triage Incident"
    static let description: IntentDescription? = IntentDescription(
        "Scores an incident 0–100, finds similar past incidents on device, and suggests the next step."
    )

    @Parameter(title: "Incident")
    var incident: IncidentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Triage \(\.$incident)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let model = try IncidentRepository.shared.incident(id: incident.id) else {
            throw WatchpostError.notFound
        }
        let brief = await IncidentRepository.shared.triage(model, donate: false)
        return .result(
            value: brief.plainText,
            dialog: "Priority \(brief.priority). \(brief.headline). Next step: \(brief.recommendedAction)"
        )
    }
}

/// "Get Open Incidents" — returns a list Shortcuts can loop over or count.
struct GetOpenIncidentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Open Incidents"
    static let description: IntentDescription? = IntentDescription(
        "Returns open incidents at or above a severity, highest first."
    )

    @Parameter(title: "Minimum Severity", default: .medium)
    var minimumSeverity: SeverityOption

    static var parameterSummary: some ParameterSummary {
        Summary("Get open incidents at \(\.$minimumSeverity) or above")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IncidentEntity]> & ProvidesDialog {
        let open = try IncidentRepository.shared.openIncidents(atLeast: minimumSeverity.severity)
        let entities = open.map { IncidentEntity($0) }
        let dialog: IntentDialog
        if let top = open.first {
            dialog = "\(open.count) open at \(minimumSeverity.label.lowercased()) or above. Top: \(top.title)."
        } else {
            dialog = "Nothing open at \(minimumSeverity.label.lowercased()) or above."
        }
        return .result(value: entities, dialog: dialog)
    }
}

/// "Resolve Incident" — close the loop from a notification, Siri, or an automation.
struct ResolveIncidentIntent: AppIntent {
    static let title: LocalizedStringResource = "Resolve Incident"
    static let description: IntentDescription? = IntentDescription("Marks an incident as resolved.")

    @Parameter(title: "Incident")
    var incident: IncidentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Resolve \(\.$incident)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = try IncidentRepository.shared.incident(id: incident.id) else {
            throw WatchpostError.notFound
        }
        try IncidentRepository.shared.setResolved(true, for: model)
        return .result(dialog: "Resolved \(model.title).")
    }
}

/// "Open Incident" — also what runs when the user taps an incident in Spotlight.
struct OpenIncidentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Incident"

    @Parameter(title: "Incident")
    var target: IncidentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationModel.shared.selectedIncidentID = target.id
        return .result()
    }
}
