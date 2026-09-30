import AppIntents
import WatchpostCore

/// App Intents-facing mirror of `Severity`. App Intents metadata is extracted from the
/// app target at build time, so the `AppEnum` conformance lives here, not in the package.
enum SeverityOption: String, AppEnum {
    case low
    case medium
    case high
    case critical

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Severity"

    static let caseDisplayRepresentations: [SeverityOption: DisplayRepresentation] = [
        .low: DisplayRepresentation(title: "Low", image: .init(systemName: "circle")),
        .medium: DisplayRepresentation(title: "Medium", image: .init(systemName: "exclamationmark.circle")),
        .high: DisplayRepresentation(title: "High", image: .init(systemName: "exclamationmark.triangle")),
        .critical: DisplayRepresentation(title: "Critical", image: .init(systemName: "flame"))
    ]

    init(_ severity: Severity) {
        switch severity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .critical: self = .critical
        }
    }

    var severity: Severity {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .critical: .critical
        }
    }

    var label: String { severity.label }
}
