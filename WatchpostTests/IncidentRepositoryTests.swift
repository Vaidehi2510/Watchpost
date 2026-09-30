import Foundation
import SwiftData
import Testing
import WatchpostCore
@testable import Watchpost

/// Exercises the repository against an in-memory store, with the deterministic
/// hashing embedder and no system side effects (Spotlight, Siri donations).
@MainActor
struct IncidentRepositoryTests {
    let repository: IncidentRepository

    init() {
        repository = IncidentRepository(
            container: AppContainer.make(inMemory: true),
            embedder: HashingEmbedder(),
            briefWriter: BriefWriter(allowsOnDeviceModel: false),
            seedBundle: nil,
            publishesSystemUpdates: false
        )
    }

    @Test func logTrimsAndPersists() throws {
        let incident = try repository.log(title: "  VPN outage  ", details: " Users cannot connect ", severity: .high, source: "Test")
        #expect(incident.title == "VPN outage")
        #expect(incident.details == "Users cannot connect")
        #expect(try repository.incident(id: incident.id) != nil)
        #expect(incident.embedding != nil)
    }

    @Test func emptyTitleIsRejected() {
        #expect(throws: WatchpostError.self) {
            try repository.log(title: "   ", severity: .low, source: "Test")
        }
    }

    @Test func longTitlesAreTruncated() throws {
        let incident = try repository.log(title: String(repeating: "x", count: 500), severity: .low, source: "Test")
        #expect(incident.title.count == IncidentRepository.maxTitleLength)
    }

    @Test func openIncidentsFilterBySeverityAndStatus() throws {
        let low = try repository.log(title: "Low thing", severity: .low, source: "Test")
        let critical = try repository.log(title: "Critical thing", severity: .critical, source: "Test")
        let resolved = try repository.log(title: "Resolved thing", severity: .critical, source: "Test")
        try repository.setResolved(true, for: resolved)

        let open = try repository.openIncidents(atLeast: .high)
        #expect(open.map(\.id) == [critical.id])
        #expect(try repository.openIncidents().map(\.id).contains(low.id))
    }

    @Test func incidentsByIDPreserveRequestedOrder() throws {
        let a = try repository.log(title: "A", severity: .low, source: "Test")
        let b = try repository.log(title: "B", severity: .critical, source: "Test")
        #expect(try repository.incidents(ids: [a.id, b.id, a.id]).map(\.id) == [a.id, b.id])
    }

    @Test func similarIncidentsRankRelatedHistoryFirstAndExcludeSelf() throws {
        let query = try repository.log(title: "VPN tunnel drops after certificate rotation", severity: .high, source: "Test")
        let related = try repository.log(title: "VPN tunnel failures after certificate renewal", severity: .high, source: "Test")
        _ = try repository.log(title: "Payroll spreadsheet shared publicly", severity: .medium, source: "Test")

        let similar = try repository.similarIncidents(to: query)
        #expect(similar.first?.id == related.id)
        #expect(!similar.contains { $0.id == query.id })
    }

    @Test func triageFallsBackToRulesWithoutTheModel() async throws {
        let incident = try repository.log(title: "Ransomware note on file server", severity: .critical, source: "Test")
        let brief = await repository.triage(incident, donate: false)
        #expect(brief.source == .rules)
        #expect(brief.priority >= 85)
    }

    @Test func deleteRemovesFromStoreAndIndex() throws {
        let a = try repository.log(title: "VPN tunnel drops", severity: .high, source: "Test")
        let b = try repository.log(title: "VPN tunnel drops again", severity: .high, source: "Test")
        let deletedID = b.id
        try repository.delete(b)
        #expect(try repository.incident(id: deletedID) == nil)
        #expect(try repository.similarIncidents(to: a).isEmpty)
    }
}
