import Foundation

/// An immutable, `Sendable` copy of an incident.
///
/// The app stores incidents in SwiftData, but SwiftData models are not `Sendable`.
/// Snapshots are what cross actor boundaries (UI -> on-device model -> App Intents).
public struct IncidentSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var details: String
    public var severity: Severity
    public var source: String
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        severity: Severity,
        source: String = "Manual",
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.severity = severity
        self.source = source
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    public var isOpen: Bool { resolvedAt == nil }

    /// The text used for embeddings and similarity search.
    public var searchableText: String {
        details.isEmpty ? title : "\(title). \(details)"
    }
}

/// A past incident that resembles the one being triaged.
public struct SimilarIncident: Identifiable, Hashable, Sendable {
    public let snapshot: IncidentSnapshot
    /// Cosine similarity in [-1, 1]; higher is more similar.
    public let score: Double

    public init(snapshot: IncidentSnapshot, score: Double) {
        self.snapshot = snapshot
        self.score = score
    }

    public var id: UUID { snapshot.id }
    public var percent: Int { Int((max(0, score) * 100).rounded()) }
}
