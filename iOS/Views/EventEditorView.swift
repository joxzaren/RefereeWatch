import SwiftUI
import RefereeKit

/// Adds an event or changes one: shirt number, team, kind, minute, or delete.
struct EventEditorView: View {
    let match: Match
    /// Nil to add a new event.
    let eventID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var confirmDelete = false

    init(match: Match, eventID: UUID?) {
        self.match = match
        self.eventID = eventID
        _draft = State(initialValue: eventID.flatMap { match.event($0) }.map(EventDraft.init(event:)) ?? EventDraft())
    }

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(EventKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("Team", selection: $draft.side) {
                    ForEach(Side.allCases, id: \.self) { side in
                        Text(match.config.name(of: side)).tag(side)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if draft.kind == .substitution {
                    numberField("Player off", text: $draft.playerOff)
                    numberField("Player on", text: $draft.playerOn)
                } else {
                    numberField("Shirt number", text: $draft.shirtNumber)
                }
            } footer: {
                Text(draft.isValid ? "Leave empty for no number." : "Enter a number from 0 to 999, or leave it empty.")
            }

            Section("When") {
                Picker("Period", selection: $draft.period) {
                    ForEach(EventDraft.periods, id: \.self) { period in
                        Text(period.title).tag(period)
                    }
                }
                Stepper("Minute \(draft.minuteBase)", value: $draft.minuteBase, in: 1...200)
                Stepper(
                    draft.minuteAdded == 0 ? "No added time" : "Added time +\(draft.minuteAdded)",
                    value: $draft.minuteAdded, in: 0...30)
            }

            if let eventID {
                Section {
                    Button("Delete event", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                model.deleteEvent(eventID, matchID: match.id)
                                dismiss()
                            }
                        }
                }
            }
        }
        .navigationTitle(eventID == nil ? "Add event" : "Edit event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if model.saveEvent(draft, eventID: eventID, matchID: match.id) { dismiss() }
                }
                .disabled(!draft.isValid)
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("No number", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
