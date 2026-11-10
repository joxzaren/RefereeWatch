import RefereeKit
import SwiftUI
import WatchKit

/// Live events with Undo last and an editor per event.
struct EventListPage: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        if let match = controller.match {
            let events = match.liveEvents
            List {
                Button {
                    controller.undoLastEvent()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Label("Undo last", systemImage: "arrow.uturn.backward")
                }
                .disabled(!events.contains { $0.createdBy == controller.deviceID })

                if events.isEmpty {
                    Text("No events yet").foregroundStyle(.secondary)
                }
                ForEach(events.reversed()) { event in
                    NavigationLink {
                        EventEditView(eventID: event.id)
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(match.config.color(of: event.side)).frame(width: 8, height: 8)
                            Text(Format.eventLine(event, config: match.config))
                                .font(.footnote)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Events")
        }
    }
}

/// Change team, kind or number, or delete the event.
struct EventEditView: View {
    @Environment(MatchController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID

    @State private var loaded = false
    @State private var kind: EventKind = .goal
    @State private var side: Side = .home
    @State private var number = 0
    @State private var playerOff = 0
    @State private var playerOn = 0
    @State private var confirmDelete = false

    var body: some View {
        if let match = controller.match, let event = match.event(eventID), event.isLive {
            ScrollView {
                VStack(spacing: 6) {
                    Text("\(event.minute.description)' \(event.period.title)").font(.footnote).foregroundStyle(.secondary)
                    Picker("Kind", selection: $kind) {
                        ForEach(EventKind.allCases, id: \.self) { kind in
                            Text(Format.short(kind)).tag(kind)
                        }
                    }
                    .frame(height: 48)
                    Picker("Team", selection: $side) {
                        Text(match.config.homeName).tag(Side.home)
                        Text(match.config.awayName).tag(Side.away)
                    }
                    .frame(height: 48)
                    if kind == .substitution {
                        HStack(spacing: 4) {
                            ShirtNumberPicker(title: "Off", number: $playerOff)
                            ShirtNumberPicker(title: "On", number: $playerOn)
                        }
                    } else {
                        ShirtNumberPicker(title: "Number", number: $number)
                    }
                    Button {
                        save()
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit")
            .onAppear { load(event) }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    controller.deleteEvent(eventID)
                    dismiss()
                }
            }
        } else {
            Text("Event deleted").foregroundStyle(.secondary)
        }
    }

    private func load(_ event: MatchEvent) {
        guard !loaded else { return }
        loaded = true
        kind = event.kind
        side = event.side
        number = event.shirtNumber ?? 0
        playerOff = event.playerOff ?? 0
        playerOn = event.playerOn ?? 0
    }

    private func save() {
        let kind = kind, side = side
        let number = number.optionalNumber, off = playerOff.optionalNumber, on = playerOn.optionalNumber
        controller.editEvent(eventID) { event in
            event.kind = kind
            event.side = side
            if kind == .substitution {
                event.shirtNumber = nil
                event.playerOff = off
                event.playerOn = on
            } else {
                event.shirtNumber = number
                event.playerOff = nil
                event.playerOn = nil
            }
        }
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}
