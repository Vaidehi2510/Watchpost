import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// How Shortcuts, Siri, and Spotlight see an incident. `@Property` values show up in
/// the Shortcuts editor, so users can filter or branch on them ("If Severity is Critical").
struct IncidentEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Incident"
    static let defaultQuery = IncidentQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Severity")
    var severity: SeverityOption

    @Property(title: "Is Open")
    var isOpen: Bool

    @Property(title: "Created")
    var createdAt: Date

    var details: String

    init(id: UUID, title: String, severity: SeverityOption, isOpen: Bool, createdAt: Date, details: String) {
        self.id = id
        self.details = details
        self.title = title
        self.severity = severity
        self.isOpen = isOpen
        self.createdAt = createdAt
    }

    @MainActor
    init(_ incident: Incident) {
        self.init(
            id: incident.id,
            title: incident.title,
            severity: SeverityOption(incident.severity),
            isOpen: incident.isOpen,
            createdAt: incident.createdAt,
            details: incident.details
        )
    }

    var displayRepresentation: DisplayRepresentation {
        let status = isOpen ? "Open" : "Resolved"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(severity.label) · \(status)",
            image: .init(systemName: SeverityStyle.symbolName(for: severity.severity))
        )
    }

    /// Spotlight metadata (Apple Intelligence can also use this index).
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = details.isEmpty ? "\(severity.label) incident" : details
        attributes.keywords = ["incident", severity.rawValue, isOpen ? "open" : "resolved"]
        return attributes
    }
}

struct IncidentQuery: EntityStringQuery {
    func entities(for identifiers: [IncidentEntity.ID]) async throws -> [IncidentEntity] {
        try await MainActor.run {
            try IncidentRepository.shared.incidents(ids: identifiers).map { IncidentEntity($0) }
        }
    }

    func entities(matching string: String) async throws -> [IncidentEntity] {
        try await MainActor.run {
            try IncidentRepository.shared.search(string).map { IncidentEntity($0) }
        }
    }

    /// Shown in the Shortcuts parameter picker and used for parameterized Siri phrases.
    func suggestedEntities() async throws -> [IncidentEntity] {
        try await MainActor.run {
            try IncidentRepository.shared.openIncidents().prefix(10).map { IncidentEntity($0) }
        }
    }
}
