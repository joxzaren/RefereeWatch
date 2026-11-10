import SwiftUI
import RefereeKit

/// The match setup form. Send passes the setup to the watch.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var sentConfirmation = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Preset") {
                Picker("Start from", selection: presetBinding) {
                    Text("Custom").tag(UUID?.none)
                    ForEach(MatchPreset.builtIn) { preset in
                        Text(preset.name).tag(UUID?.some(preset.id))
                    }
                }
            }

            Section("Teams") {
                teamRow(title: "Home", name: $model.draft.homeName, hex: $model.draft.homeColorHex)
                teamRow(title: "Away", name: $model.draft.awayName, hex: $model.draft.awayColorHex)
            }

            Section("Match") {
                TextField("Competition", text: $model.draft.competition)
                Toggle("Kick off time", isOn: $model.draft.hasKickOff)
                if model.draft.hasKickOff {
                    DatePicker("Kick off", selection: $model.draft.kickOff)
                }
            }

            Section("Timings") {
                minutesStepper("Half length", value: timing(\.halfMinutes), range: 1...60)
                minutesStepper("Half time", value: timing(\.halfTimeMinutes), range: 0...30)
            }

            Section {
                ForEach(model.draft.warningMinutes.indices, id: \.self) { index in
                    minutesStepper(
                        "Warning \(index + 1)",
                        value: warning(at: index),
                        range: 1...max(model.draft.halfMinutes - 1, 1),
                        suffix: "before end")
                }
                .onDelete { offsets in
                    model.draft.warningMinutes.remove(atOffsets: offsets)
                    model.draft.presetID = nil
                }
                if model.draft.warningMinutes.count < 4 {
                    Button("Add warning") {
                        model.draft.warningMinutes.append(1)
                        model.draft.presetID = nil
                    }
                }
            } header: {
                Text("Warnings")
            } footer: {
                Text("The watch alerts you this many minutes before the end of each half. Swipe to remove one.")
            }

            Section("Extra time and penalties") {
                Toggle("Extra time", isOn: timing(\.extraTimeEnabled))
                if model.draft.extraTimeEnabled {
                    minutesStepper("Extra time half", value: timing(\.extraTimeHalfMinutes), range: 1...30)
                    minutesStepper("Break before", value: timing(\.extraTimeBreakMinutes), range: 0...15)
                    minutesStepper("Break between halves", value: timing(\.extraTimeHalfTimeMinutes), range: 0...10)
                }
                Toggle("Penalties", isOn: timing(\.penaltiesEnabled))
            }

            Section {
                Button(model.isEditingSentMatch ? "Send update to watch" : "Send to watch") {
                    model.sendSetup()
                    sentConfirmation = true
                }
                .frame(maxWidth: .infinity)
                .bold()
            } footer: {
                if let last = model.lastSetup, model.isEditingSentMatch {
                    Text("Last sent \(last.version.modifiedAt.formatted(date: .omitted, time: .shortened)): \(last.config.homeName) v \(last.config.awayName). Sending again replaces it on the watch until kick off.")
                }
            }
        }
        .navigationTitle(model.isEditingSentMatch ? "Edit match" : "New match")
        .toolbar {
            if model.isEditingSentMatch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New match", systemImage: "plus") { model.startNewSetup() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: sentConfirmation) { _, new in new }
        .alert("Sent to watch", isPresented: $sentConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The watch shows this setup the next time it connects. Edit and send again to change it before kick off.")
        }
    }

    // MARK: Bindings

    private var presetBinding: Binding<UUID?> {
        Binding(
            get: { model.draft.presetID },
            set: { id in
                if let id, let preset = MatchPreset.builtIn.first(where: { $0.id == id }) {
                    model.draft.apply(preset)
                } else {
                    model.draft.presetID = nil
                }
            })
    }

    /// A binding to a timing field. Changing it means the form no longer matches the preset.
    private func timing<Value: Equatable>(_ keyPath: WritableKeyPath<SetupDraft, Value>) -> Binding<Value> {
        Binding(
            get: { model.draft[keyPath: keyPath] },
            set: { value in
                guard model.draft[keyPath: keyPath] != value else { return }
                model.draft[keyPath: keyPath] = value
                model.draft.presetID = nil
            })
    }

    /// A binding to one warning that tolerates the row being removed while it is still on screen.
    private func warning(at index: Int) -> Binding<Int> {
        Binding(
            get: { model.draft.warningMinutes.indices.contains(index) ? model.draft.warningMinutes[index] : 1 },
            set: { value in
                guard model.draft.warningMinutes.indices.contains(index),
                      model.draft.warningMinutes[index] != value else { return }
                model.draft.warningMinutes[index] = value
                model.draft.presetID = nil
            })
    }

    // MARK: Rows

    private func teamRow(title: String, name: Binding<String>, hex: Binding<String>) -> some View {
        HStack {
            TextField(title, text: name)
                .textInputAutocapitalization(.words)
            ColorPicker(
                "\(title) colour",
                selection: Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexString }),
                supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func minutesStepper(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String = ""
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: suffix.isEmpty ? "\(value.wrappedValue) min" : "\(value.wrappedValue) min \(suffix)")
        }
    }
}
