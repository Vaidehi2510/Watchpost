import Foundation

/// The output shown in the app, spoken by Siri, and returned to Shortcuts.
public struct TriageBrief: Hashable, Sendable, Codable {
    public enum Source: String, Codable, Sendable {
        /// Deterministic rules in `TriageEngine`. Always available.
        case rules
        /// Apple's on-device Foundation Model (Apple Intelligence devices only).
        case onDeviceModel
    }

    public var headline: String
    public var recommendedAction: String
    public var rationale: String
    /// 0–100. Always computed by `TriageEngine`, even when the text comes from the model,
    /// so ranking stays deterministic and testable.
    public var priority: Int
    public var source: Source

    public init(headline: String, recommendedAction: String, rationale: String, priority: Int, source: Source) {
        self.headline = headline
        self.recommendedAction = recommendedAction
        self.rationale = rationale
        self.priority = priority
        self.source = source
    }

    public var plainText: String {
        "[\(priority)/100] \(headline)\nNext step: \(recommendedAction)\nWhy: \(rationale)"
    }
}

/// Rule-based triage: priority scoring plus a fallback brief.
public enum TriageEngine {
    /// Similarity at or above this counts as a recurrence of a past incident.
    public static let recurrenceThreshold = 0.6

    struct Indicator: Sendable {
        let keyword: String
        let action: String
    }

    /// Checked in order; the first match decides the recommended action.
    static let indicators: [Indicator] = [
        Indicator(keyword: "ransomware", action: "Isolate affected hosts from the network and preserve disk images before remediating."),
        Indicator(keyword: "exfiltration", action: "Block the destination at the egress firewall and scope what data left the network."),
        Indicator(keyword: "credential", action: "Force a credential reset for affected accounts and review recent sign-ins."),
        Indicator(keyword: "phishing", action: "Pull the message from all inboxes and reset credentials for anyone who clicked."),
        Indicator(keyword: "privilege", action: "Revoke the elevated role and audit changes made while it was active."),
        Indicator(keyword: "malware", action: "Quarantine the endpoint and collect the sample for analysis."),
        Indicator(keyword: "vpn", action: "Check tunnel logs and certificate validity on the VPN gateway."),
        Indicator(keyword: "certificate", action: "Verify the certificate chain and expiry on the affected service."),
        Indicator(keyword: "ddos", action: "Enable upstream rate limiting and confirm the origin stays reachable.")
    ]

    public static func matchedIndicators(in incident: IncidentSnapshot) -> [String] {
        // Prefix match so "credential" also catches "credentials" and "privilege" catches "privileged".
        let tokens = Tokenizer.tokens(in: incident.searchableText)
        return indicators
            .filter { indicator in tokens.contains { $0.hasPrefix(indicator.keyword) } }
            .map { $0.keyword }
    }

    /// 0–100 priority: severity base + recency + recurrence + threat indicators,
    /// minus 30 if already resolved.
    public static func priority(
        for incident: IncidentSnapshot,
        recurrences: Int,
        now: Date = Date()
    ) -> Int {
        var score = incident.severity.basePriority
        let age = now.timeIntervalSince(incident.createdAt)
        if age < 3_600 {
            score += 10
        } else if age < 86_400 {
            score += 5
        }
        score += min(max(recurrences, 0), 2) * 5
        score += min(matchedIndicators(in: incident).count, 2) * 5
        if !incident.isOpen {
            score -= 30
        }
        return min(100, max(0, score))
    }

    public static func brief(
        for incident: IncidentSnapshot,
        similar: [SimilarIncident],
        now: Date = Date()
    ) -> TriageBrief {
        let recurrences = similar.filter { $0.score >= recurrenceThreshold }
        let found = matchedIndicators(in: incident)
        let score = Self.priority(for: incident, recurrences: recurrences.count, now: now)

        var headline = "\(incident.severity.label) incident: \(incident.title)"
        if !recurrences.isEmpty {
            let noun = recurrences.count == 1 ? "incident" : "incidents"
            headline += " (resembles \(recurrences.count) past \(noun))"
        }

        let action: String
        if !incident.isOpen {
            action = "Confirm the fix held and record the root cause."
        } else if let keyword = found.first, let match = indicators.first(where: { $0.keyword == keyword }) {
            action = match.action
        } else {
            switch incident.severity {
            case .critical: action = "Page the on-call owner now and open an incident bridge."
            case .high: action = "Assign an owner within the hour and start containment."
            case .medium: action = "Queue for today's triage review and gather logs."
            case .low: action = "Track in the backlog and batch with similar low-severity items."
            }
        }

        var reasons = ["\(incident.severity.label) severity sets a base of \(incident.severity.basePriority)."]
        if let top = similar.first {
            let status = top.snapshot.isOpen ? "still open" : "resolved"
            reasons.append("Closest match: \"\(top.snapshot.title)\" (\(top.percent)% similar, \(status)).")
        }
        if !found.isEmpty {
            reasons.append("Indicators: \(found.joined(separator: ", ")).")
        }

        return TriageBrief(
            headline: headline,
            recommendedAction: action,
            rationale: reasons.joined(separator: " "),
            priority: score,
            source: .rules
        )
    }
}

/// Builds the prompt for the on-device language model. Kept here so it is unit-testable.
public enum PromptFormatter {
    public static func prompt(for incident: IncidentSnapshot, similar: [SimilarIncident]) -> String {
        var lines = [
            "Incident: \(incident.title)",
            "Severity: \(incident.severity.label)",
            "Status: \(incident.isOpen ? "Open" : "Resolved")",
            "Source: \(incident.source)"
        ]
        if !incident.details.isEmpty {
            lines.append("Details: \(incident.details)")
        }
        if similar.isEmpty {
            lines.append("No similar past incidents were found.")
        } else {
            lines.append("Similar past incidents:")
            for match in similar.prefix(3) {
                let status = match.snapshot.isOpen ? "open" : "resolved"
                lines.append("- \(match.snapshot.title) (\(match.percent)% similar, \(status))")
            }
        }
        lines.append("Write a triage brief for the on-call engineer.")
        return lines.joined(separator: "\n")
    }
}
