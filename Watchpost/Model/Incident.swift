import Foundation
import SwiftData
import WatchpostCore

/// Persistent incident record. Severity is stored as an `Int` so it can be used
/// directly in `#Predicate` filters and sort descriptors.
@Model
final class Incident {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var severityRaw: Int
    var source: String
    var createdAt: Date
    var resolvedAt: Date?

    /// Cached sentence embedding, so similarity search never re-embeds history.
    var embedding: [Double]?
    /// `TextEmbedder.identifier` that produced `embedding`; a mismatch triggers re-embedding.
    var embeddingModel: String?

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        severity: Severity,
        source: String = "Manual",
        createdAt: Date = .now,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.severityRaw = severity.rawValue
        self.source = source
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

extension Incident {
    var severity: Severity {
        get { Severity(rawValue: severityRaw) ?? .low }
        set { severityRaw = newValue.rawValue }
    }

    var isOpen: Bool { resolvedAt == nil }

    var snapshot: IncidentSnapshot {
        IncidentSnapshot(
            id: id,
            title: title,
            details: details,
            severity: severity,
            source: source,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }
}

enum WatchpostError: Error, CustomLocalizedStringResourceConvertible {
    case emptyTitle
    case notFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyTitle: "An incident needs a title."
        case .notFound: "That incident no longer exists."
        }
    }
}
