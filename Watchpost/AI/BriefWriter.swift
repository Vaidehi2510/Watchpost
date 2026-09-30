import Foundation
import WatchpostCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes the triage brief. Uses Apple's on-device Foundation Model when the device
/// supports Apple Intelligence, and falls back to the deterministic rules engine
/// everywhere else. Either way, nothing leaves the device.
struct BriefWriter: Sendable {
    var allowsOnDeviceModel = true

    func brief(for incident: IncidentSnapshot, similar: [SimilarIncident], now: Date = .now) async -> TriageBrief {
        let baseline = TriageEngine.brief(for: incident, similar: similar, now: now)
        guard allowsOnDeviceModel else { return baseline }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if let generated = try? await OnDeviceBriefModel.generate(for: incident, similar: similar) {
                // Keep the rules-based priority so ranking stays deterministic.
                return TriageBrief(
                    headline: generated.headline,
                    recommendedAction: generated.recommendedAction,
                    rationale: generated.rationale,
                    priority: baseline.priority,
                    source: .onDeviceModel
                )
            }
        }
        #endif

        return baseline
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedBrief {
    @Guide(description: "A one-sentence headline for the on-call engineer, under 16 words.")
    var headline: String

    @Guide(description: "The single most important next action, as one imperative sentence.")
    var recommendedAction: String

    @Guide(description: "Two short sentences explaining why, citing similar past incidents when given.")
    var rationale: String
}

@available(iOS 26.0, macOS 26.0, *)
enum OnDeviceBriefModel {
    static func generate(for incident: IncidentSnapshot, similar: [SimilarIncident]) async throws -> GeneratedBrief? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(
            instructions: "You are a calm, precise incident-response assistant. Use only the facts provided. Never invent hosts, users, or indicators."
        )
        let prompt = PromptFormatter.prompt(for: incident, similar: similar)
        let response = try await session.respond(to: prompt, generating: GeneratedBrief.self)
        return response.content
    }
}
#endif
