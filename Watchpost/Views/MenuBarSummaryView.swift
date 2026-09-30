#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import WatchpostCore

/// macOS menu bar glance: open counts by severity and the top three incidents.
struct MenuBarSummaryView: View {
    @Environment(NavigationModel.self) private var navigation
    @Query(filter: #Predicate<Incident> { $0.resolvedAt == nil }, sort: IncidentRepository.defaultSort)
    private var openIncidents: [Incident]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open Incidents")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(Severity.allCases.reversed(), id: \.self) { level in
                    let count = openIncidents.filter { $0.severity == level }.count
                    VStack {
                        Text("\(count)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SeverityStyle.color(for: level))
                        Text(level.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Divider()

            if openIncidents.isEmpty {
                Label("All clear", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openIncidents.prefix(3)) { incident in
                    Button {
                        open(incident)
                    } label: {
                        HStack {
                            Image(systemName: SeverityStyle.symbolName(for: incident.severity))
                                .foregroundStyle(SeverityStyle.color(for: incident.severity))
                            Text(incident.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Button("Open Watchpost") { NSApplication.shared.activate() }
        }
        .padding()
        .frame(width: 300)
    }

    private func open(_ incident: Incident) {
        navigation.selectedIncidentID = incident.id
        NSApplication.shared.activate()
    }
}
#endif
