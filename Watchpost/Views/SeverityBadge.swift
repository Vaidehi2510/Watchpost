import SwiftUI
import WatchpostCore

enum SeverityStyle {
    static func symbolName(for severity: Severity) -> String {
        switch severity {
        case .low: "circle"
        case .medium: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        case .critical: "flame"
        }
    }

    static func color(for severity: Severity) -> Color {
        switch severity {
        case .low: .gray
        case .medium: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Label(severity.label, systemImage: SeverityStyle.symbolName(for: severity))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(SeverityStyle.color(for: severity))
            .background(SeverityStyle.color(for: severity).opacity(0.15), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Severity: \(severity.label)")
    }
}

/// A 0–100 priority meter with a text value for VoiceOver.
struct PriorityMeter: View {
    let priority: Int

    private var tint: Color {
        switch priority {
        case 80...: .red
        case 55..<80: .orange
        case 30..<55: .yellow
        default: .gray
        }
    }

    var body: some View {
        Gauge(value: Double(priority), in: 0...100) {
            Text("Priority")
        } currentValueLabel: {
            Text("\(priority)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(tint)
        .accessibilityValue("\(priority) out of 100")
    }
}
