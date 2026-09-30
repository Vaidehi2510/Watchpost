import Foundation

/// How urgent an incident is. Ordered so `critical > high > medium > low`.
public enum Severity: Int, CaseIterable, Codable, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    /// Starting point for the 0–100 triage priority score.
    public var basePriority: Int {
        switch self {
        case .low: 15
        case .medium: 40
        case .high: 65
        case .critical: 85
        }
    }

    /// Parses labels such as "high" or "Critical" (case-insensitive).
    public init?(label: String) {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Severity.allCases.first(where: { $0.label.lowercased() == normalized }) else {
            return nil
        }
        self = match
    }
}
