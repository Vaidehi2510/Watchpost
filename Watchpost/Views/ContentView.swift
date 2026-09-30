import SwiftData
import SwiftUI
import WatchpostCore

enum IncidentFilter: String, CaseIterable, Identifiable {
    case open = "Open"
    case critical = "High+"
    case all = "All"

    var id: String { rawValue }

    func includes(_ incident: Incident) -> Bool {
        switch self {
        case .open: incident.isOpen
        case .critical: incident.isOpen && incident.severity >= .high
        case .all: true
        }
    }
}

struct ContentView: View {
    @Environment(NavigationModel.self) private var navigation
    @Query(sort: IncidentRepository.defaultSort) private var incidents: [Incident]

    @State private var filter: IncidentFilter = .open
    @State private var searchText = ""
    @State private var isAddingIncident = false

    private var visibleIncidents: [Incident] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return incidents.filter { incident in
            filter.includes(incident)
                && (term.isEmpty
                    || incident.title.localizedStandardContains(term)
                    || incident.details.localizedStandardContains(term))
        }
    }

    var body: some View {
        @Bindable var nav = navigation

        NavigationSplitView {
            IncidentListView(incidents: visibleIncidents, selection: $nav.selectedIncidentID)
                .navigationTitle("Watchpost")
                .searchable(text: $searchText, prompt: "Search incidents")
                .safeAreaInset(edge: .top) {
                    Picker("Filter", selection: $filter) {
                        ForEach(IncidentFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Incident", systemImage: "plus") { isAddingIncident = true }
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
        } detail: {
            if let id = nav.selectedIncidentID, let incident = incidents.first(where: { $0.id == id }) {
                IncidentDetailView(incident: incident)
                    .id(incident.id)
            } else {
                ContentUnavailableView(
                    "No Incident Selected",
                    systemImage: "shield.lefthalf.filled",
                    description: Text("Pick an incident to see its triage brief and similar history.")
                )
            }
        }
        .sheet(isPresented: $isAddingIncident) {
            NewIncidentView { created in nav.selectedIncidentID = created.id }
        }
    }
}

struct IncidentListView: View {
    let incidents: [Incident]
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(incidents) { incident in
                NavigationLink(value: incident.id) {
                    IncidentRow(incident: incident)
                }
                .swipeActions(edge: .leading) {
                    Button(incident.isOpen ? "Resolve" : "Reopen",
                           systemImage: incident.isOpen ? "checkmark.circle" : "arrow.uturn.backward") {
                        try? IncidentRepository.shared.setResolved(incident.isOpen, for: incident)
                    }
                    .tint(incident.isOpen ? .green : .blue)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if selection == incident.id { selection = nil }
                        try? IncidentRepository.shared.delete(incident)
                    }
                }
            }
        }
        .overlay {
            if incidents.isEmpty {
                ContentUnavailableView("All Clear", systemImage: "checkmark.shield",
                                       description: Text("No incidents match this filter."))
            }
        }
    }
}

struct IncidentRow: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(incident.title)
                    .font(.headline)
                    .lineLimit(2)
                    .strikethrough(!incident.isOpen)
                Spacer(minLength: 8)
                SeverityBadge(severity: incident.severity)
            }
            Text("\(incident.source) · \(incident.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
