import SwiftUI
import RefereeKit

/// The match report. Tap an event to edit it; share the PDF from the toolbar.
struct ReportView: View {
    let matchID: UUID
    @Environment(AppModel.self) private var model
    @State private var editing: EditorTarget?

    var body: some View {
        if let match = model.match(matchID) {
            report(match, layout: ReportLayout(match: match))
        } else {
            ContentUnavailableView("Match not found", systemImage: "questionmark.circle")
        }
    }

    private func report(_ match: Match, layout: ReportLayout) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(layout.title).font(.title2.bold())
                    if !layout.subtitle.isEmpty {
                        Text(layout.subtitle).foregroundStyle(.secondary)
                    }
                    Text(layout.score).font(.title3.monospacedDigit())
                    if let penalties = layout.penalties {
                        Text(penalties).monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }

            if !layout.hasEvents {
                Section("Events") {
                    Text("No events logged").foregroundStyle(.secondary)
                }
            }

            ForEach(layout.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        if let eventID = row.eventID {
                            Button {
                                editing = EditorTarget(eventID: eventID)
                            } label: {
                                ReportRowView(row: row)
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    model.deleteEvent(eventID, matchID: match.id)
                                }
                            }
                        } else {
                            ReportRowView(row: row)
                        }
                    }
                }
            }

            if !layout.workout.isEmpty {
                Section("Workout") {
                    ForEach(layout.workout) { row in
                        if let lead = row.lead {
                            LabeledContent(lead, value: row.text)
                        } else {
                            Label(row.text, systemImage: "heart.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add event", systemImage: "plus") {
                    editing = EditorTarget(eventID: nil)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                let fileName = ReportFileName.make(match: match)
                ShareLink(
                    item: ReportPDF(fileName: fileName, data: ReportPDFRenderer.render(layout)),
                    preview: SharePreview(fileName, image: Image(systemName: "doc.richtext")))
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                EventEditorView(match: match, eventID: target.eventID)
            }
        }
    }
}

struct EditorTarget: Identifiable {
    var eventID: UUID?
    var id: String { eventID?.uuidString ?? "new" }
}

struct ReportRowView: View {
    let row: ReportLayout.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let lead = row.lead {
                Text(lead)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            Text(row.text)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
