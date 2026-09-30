import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import WatchpostCore

/// Single source of truth for reads and writes. The UI, every App Intent, and the
/// Spotlight query all go through here, on the main actor's `ModelContext`, so a change
/// made from Siri or Shortcuts shows up in open `@Query` views immediately.
@MainActor
final class IncidentRepository {
    static let shared = IncidentRepository(container: AppContainer.shared)

    nonisolated static let maxTitleLength = 120
    /// Matches below this are too weak to show as "similar".
    nonisolated static let minimumSimilarity = 0.35
    nonisolated static let defaultSort = [
        SortDescriptor(\Incident.severityRaw, order: .reverse),
        SortDescriptor(\Incident.createdAt, order: .reverse)
    ]

    let container: ModelContainer
    let context: ModelContext
    private let embedder: any TextEmbedder
    private let briefWriter: BriefWriter
    private let publishesSystemUpdates: Bool
    private var index = SimilarityIndex()
    private var indexIsWarm = false

    /// - Parameter publishesSystemUpdates: set `false` in tests to skip Spotlight and
    ///   Shortcuts side effects.
    init(
        container: ModelContainer,
        embedder: any TextEmbedder = EmbedderFactory.best(),
        briefWriter: BriefWriter = BriefWriter(),
        seedBundle: Bundle? = .main,
        publishesSystemUpdates: Bool = true
    ) {
        self.container = container
        self.context = container.mainContext
        self.embedder = embedder
        self.briefWriter = briefWriter
        self.publishesSystemUpdates = publishesSystemUpdates
        if let seedBundle {
            try? seedIfNeeded(from: seedBundle)
        }
    }

    // MARK: - Reads

    func fetchAll() throws -> [Incident] {
        try context.fetch(FetchDescriptor<Incident>(sortBy: Self.defaultSort))
    }

    func openIncidents(atLeast minimum: Severity = .low) throws -> [Incident] {
        let minimumRaw = minimum.rawValue
        let descriptor = FetchDescriptor<Incident>(
            predicate: #Predicate<Incident> { $0.resolvedAt == nil && $0.severityRaw >= minimumRaw },
            sortBy: Self.defaultSort
        )
        return try context.fetch(descriptor)
    }

    func incident(id: UUID) throws -> Incident? {
        var descriptor = FetchDescriptor<Incident>(predicate: #Predicate<Incident> { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Returns incidents in the same order as `ids` (App Intents expects this).
    func incidents(ids: [UUID]) throws -> [Incident] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Incident>(predicate: #Predicate<Incident> { ids.contains($0.id) })
        let found = try context.fetch(descriptor)
        let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return found.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    func search(_ text: String, limit: Int = 25) throws -> [Incident] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return try fetchAll() }
        var descriptor = FetchDescriptor<Incident>(
            predicate: #Predicate<Incident> {
                $0.title.localizedStandardContains(term) || $0.details.localizedStandardContains(term)
            },
            sortBy: Self.defaultSort
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Writes

    @discardableResult
    func log(title: String, details: String = "", severity: Severity, source: String) throws -> Incident {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw WatchpostError.emptyTitle }
        let incident = Incident(
            title: String(cleanTitle.prefix(Self.maxTitleLength)),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            severity: severity,
            source: source
        )
        context.insert(incident)
        embedIfNeeded(incident)
        try context.save()
        publish(changed: [incident])
        return incident
    }

    func setResolved(_ resolved: Bool, for incident: Incident) throws {
        incident.resolvedAt = resolved ? .now : nil
        try context.save()
        publish(changed: [incident])
    }

    func delete(_ incident: Incident) throws {
        let id = incident.id
        context.delete(incident)
        try context.save()
        index.remove(id)
        guard publishesSystemUpdates else { return }
        Task {
            try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: IncidentEntity.self)
        }
        WatchpostShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Similarity and triage

    func similarIncidents(to incident: Incident, limit: Int = 3) throws -> [SimilarIncident] {
        try warmIndexIfNeeded()
        guard let query = embedIfNeeded(incident) else { return [] }
        let matches = index.nearest(
            to: query,
            k: limit,
            excluding: [incident.id],
            minimumScore: Self.minimumSimilarity
        )
        let found = try incidents(ids: matches.map(\.id))
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return matches.compactMap { match in
            byID[match.id].map { SimilarIncident(snapshot: $0.snapshot, score: match.score) }
        }
    }

    /// Builds a triage brief. `donate` is true when the user triaged from the UI, so the
    /// system can learn the pattern and suggest this action proactively.
    func triage(_ incident: Incident, donate: Bool) async -> TriageBrief {
        let similar = (try? similarIncidents(to: incident)) ?? []
        let brief = await briefWriter.brief(for: incident.snapshot, similar: similar)
        if donate, publishesSystemUpdates {
            var intent = TriageIncidentIntent()
            intent.incident = IncidentEntity(incident)
            Task { [intent] in _ = try? await IntentDonationManager.shared.donate(intent: intent) }
        }
        return brief
    }

    // MARK: - Setup

    func seedIfNeeded(from bundle: Bundle) throws {
        guard try context.fetchCount(FetchDescriptor<Incident>()) == 0 else { return }
        let now = Date.now
        for record in SeedLoader.load(from: bundle) {
            let created = now.addingTimeInterval(-record.hoursAgo * 3_600)
            context.insert(Incident(
                title: record.title,
                details: record.details,
                severity: Severity(label: record.severity) ?? .medium,
                source: record.source,
                createdAt: created,
                resolvedAt: record.resolved ? created.addingTimeInterval(2 * 3_600) : nil
            ))
        }
        try context.save()
    }

    /// Called at launch: embeds anything new, then refreshes Spotlight and Shortcuts.
    func bootstrap() async {
        try? warmIndexIfNeeded()
        guard publishesSystemUpdates, let all = try? fetchAll() else { return }
        try? await CSSearchableIndex.default().indexAppEntities(all.map { IncidentEntity($0) })
        WatchpostShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Private

    @discardableResult
    private func embedIfNeeded(_ incident: Incident) -> [Double]? {
        if let cached = incident.embedding, incident.embeddingModel == embedder.identifier {
            index.upsert(incident.id, vector: cached)
            return cached
        }
        guard let vector = embedder.embed(incident.snapshot.searchableText) else { return nil }
        incident.embedding = vector
        incident.embeddingModel = embedder.identifier
        index.upsert(incident.id, vector: vector)
        return vector
    }

    private func warmIndexIfNeeded() throws {
        guard !indexIsWarm else { return }
        for incident in try fetchAll() {
            embedIfNeeded(incident)
        }
        if context.hasChanges {
            try context.save()
        }
        indexIsWarm = true
    }

    private func publish(changed incidents: [Incident]) {
        guard publishesSystemUpdates else { return }
        let entities = incidents.map { IncidentEntity($0) }
        Task { try? await CSSearchableIndex.default().indexAppEntities(entities) }
        WatchpostShortcuts.updateAppShortcutParameters()
    }
}

struct SeedRecord: Decodable {
    let title: String
    let details: String
    let severity: String
    let source: String
    let hoursAgo: Double
    let resolved: Bool
}

enum SeedLoader {
    static func load(from bundle: Bundle) -> [SeedRecord] {
        guard
            let url = bundle.url(forResource: "SeedIncidents", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([SeedRecord].self, from: data)) ?? []
    }
}
