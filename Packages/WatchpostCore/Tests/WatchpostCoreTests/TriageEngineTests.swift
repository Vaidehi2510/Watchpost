import XCTest
@testable import WatchpostCore

final class TriageEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func incident(
        _ title: String,
        details: String = "",
        severity: Severity,
        hoursAgo: Double = 48,
        resolved: Bool = false
    ) -> IncidentSnapshot {
        IncidentSnapshot(
            title: title,
            details: details,
            severity: severity,
            createdAt: now.addingTimeInterval(-hoursAgo * 3_600),
            resolvedAt: resolved ? now : nil
        )
    }

    func testHigherSeverityAlwaysRanksHigher() {
        let scores = Severity.allCases.map {
            TriageEngine.priority(for: incident("Disk usage alert", severity: $0), recurrences: 0, now: now)
        }
        XCTAssertEqual(scores, scores.sorted())
        XCTAssertEqual(Set(scores).count, Severity.allCases.count)
    }

    func testRecencyAddsPriority() {
        let fresh = TriageEngine.priority(for: incident("Alert", severity: .medium, hoursAgo: 0.5), recurrences: 0, now: now)
        let today = TriageEngine.priority(for: incident("Alert", severity: .medium, hoursAgo: 5), recurrences: 0, now: now)
        let old = TriageEngine.priority(for: incident("Alert", severity: .medium, hoursAgo: 48), recurrences: 0, now: now)
        XCTAssertEqual([fresh, today, old], [50, 45, 40])
    }

    func testPriorityIsClampedTo100() {
        let worst = incident(
            "Ransomware on file server",
            details: "Credential theft suspected",
            severity: .critical,
            hoursAgo: 0.1
        )
        // 85 base + 10 recency + 10 recurrences + 10 indicators = 115 -> clamped
        XCTAssertEqual(TriageEngine.priority(for: worst, recurrences: 5, now: now), 100)
    }

    func testResolvedIncidentsDropPriority() {
        let open = incident("Alert", severity: .high)
        let resolved = incident("Alert", severity: .high, resolved: true)
        XCTAssertEqual(
            TriageEngine.priority(for: open, recurrences: 0, now: now) - 30,
            TriageEngine.priority(for: resolved, recurrences: 0, now: now)
        )
    }

    func testIndicatorsUsePrefixMatching() {
        let found = TriageEngine.matchedIndicators(
            in: incident("Leaked credentials", details: "Privileged account used", severity: .high)
        )
        XCTAssertEqual(found, ["credential", "privilege"])
    }

    func testRansomwareBriefRecommendsIsolation() {
        let brief = TriageEngine.brief(
            for: incident("Ransomware note on file server", severity: .critical),
            similar: [],
            now: now
        )
        XCTAssertTrue(brief.recommendedAction.hasPrefix("Isolate"))
        XCTAssertEqual(brief.source, .rules)
    }

    func testBriefMentionsRecurrenceAndClosestMatch() {
        let past = incident("VPN tunnel flapping", severity: .high, resolved: true)
        let brief = TriageEngine.brief(
            for: incident("VPN tunnel drops", severity: .high),
            similar: [SimilarIncident(snapshot: past, score: 0.82)],
            now: now
        )
        XCTAssertTrue(brief.headline.contains("resembles 1 past incident"))
        XCTAssertTrue(brief.rationale.contains("82% similar"))
    }

    func testPromptIncludesFactsAndSimilarHistory() {
        let past = incident("Certificate expired on gateway", severity: .medium, resolved: true)
        let prompt = PromptFormatter.prompt(
            for: incident("VPN outage", details: "Users cannot connect", severity: .high),
            similar: [SimilarIncident(snapshot: past, score: 0.7)]
        )
        XCTAssertTrue(prompt.contains("Severity: High"))
        XCTAssertTrue(prompt.contains("Details: Users cannot connect"))
        XCTAssertTrue(prompt.contains("- Certificate expired on gateway (70% similar, resolved)"))
    }

    func testSeverityParsesLabels() {
        XCTAssertEqual(Severity(label: " critical "), .critical)
        XCTAssertNil(Severity(label: "urgent"))
    }
}
