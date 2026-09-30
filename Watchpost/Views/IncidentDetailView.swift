import SwiftUI
import WatchpostCore

struct IncidentDetailView: View {
    @Environment(NavigationModel.self) private var navigation
    let incident: Incident

    @State private var similar: [SimilarIncident] = []
    @State private var brief: TriageBrief?
    @State private var isTriaging = false
    @State private var errorMessage: String?

    init(incident: Incident) {
        self.incident = incident
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SeverityBadge(severity: incident.severity)
                        Text(incident.isOpen ? "Open" : "Resolved")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(incident.isOpen ? .orange : .green)
                    }
                    Text(incident.title)
                        .font(.title2.weight(.semibold))
                    if !incident.details.isEmpty {
                        Text(incident.details)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("\(incident.source) · \(incident.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }

            Section("Triage Brief") {
                if let brief {
                    BriefView(brief: brief)
                } else {
                    Button {
                        Task { await runTriage() }
                    } label: {
                        if isTriaging {
                            ProgressView()
                        } else {
                            Label("Generate Brief", systemImage: "sparkles")
                        }
                    }
                    .disabled(isTriaging)
                }
            }

            Section("Similar Past Incidents") {
                if similar.isEmpty {
                    Text("No close matches in history.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(similar) { match in
                        Button {
                            navigation.selectedIncidentID = match.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(match.snapshot.title)
                                    Text(match.snapshot.isOpen ? "Open" : "Resolved")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(match.percent)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(match.snapshot.title), \(match.percent) percent similar")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(incident.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button(incident.isOpen ? "Resolve" : "Reopen",
                       systemImage: incident.isOpen ? "checkmark.circle" : "arrow.uturn.backward") {
                    toggleResolved()
                }
            }
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: incident.id) {
            similar = (try? IncidentRepository.shared.similarIncidents(to: incident)) ?? []
        }
    }

    private func runTriage() async {
        isTriaging = true
        defer { isTriaging = false }
        brief = await IncidentRepository.shared.triage(incident, donate: true)
        PlatformBridge.notifySuccess()
    }

    private func toggleResolved() {
        do {
            try IncidentRepository.shared.setResolved(incident.isOpen, for: incident)
            brief = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BriefView: View {
    let brief: TriageBrief

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PriorityMeter(priority: brief.priority)
            VStack(alignment: .leading, spacing: 6) {
                Text(brief.headline)
                    .font(.headline)
                Label(brief.recommendedAction, systemImage: "arrow.right.circle")
                Text(brief.rationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(
                        brief.source == .onDeviceModel ? "On-device model" : "Rules engine",
                        systemImage: brief.source == .onDeviceModel ? "apple.intelligence" : "list.bullet.rectangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        PlatformBridge.copyToPasteboard(brief.plainText)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
