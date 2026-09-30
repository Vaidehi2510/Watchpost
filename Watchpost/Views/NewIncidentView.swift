import AppIntents
import SwiftUI
import WatchpostCore

struct NewIncidentView: View {
    @Environment(\.dismiss) private var dismiss
    private let onCreate: (Incident) -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var severity: Severity = .medium
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(onCreate: @escaping (Incident) -> Void = { _ in }) {
        self.onCreate = onCreate
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= IncidentRepository.maxTitleLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.next)
                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("\(trimmedTitle.count)/\(IncidentRepository.maxTitleLength)")
                        .monospacedDigit()
                        .foregroundStyle(trimmedTitle.count > IncidentRepository.maxTitleLength ? Color.red : Color.secondary)
                }

                Section("Severity") {
                    Picker("Severity", selection: $severity) {
                        ForEach(Severity.allCases, id: \.self) { level in
                            Label(level.label, systemImage: SeverityStyle.symbolName(for: level)).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Incident")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear { titleFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func save() {
        do {
            let incident = try IncidentRepository.shared.log(
                title: trimmedTitle,
                details: details,
                severity: severity,
                source: "Manual"
            )
            donateLogIntent()
            PlatformBridge.notifySuccess()
            onCreate(incident)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lets the system learn "the user logs a <severity> incident" and suggest it proactively.
    private func donateLogIntent() {
        var intent = LogIncidentIntent()
        intent.severity = SeverityOption(severity)
        Task { [intent] in _ = try? await IntentDonationManager.shared.donate(intent: intent) }
    }
}
