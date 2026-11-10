import CoreGraphics
import Foundation
import Testing
import RefereeKit
@testable import RefereeWatch

enum Fixtures {
    static let deviceID = "watch-A"
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-10 14:30:00 UTC.
    static let kickOff = Date(timeIntervalSince1970: 1_794_321_000)

    /// Lions 2 - 2 Bears, a booking, a substitution, a goal without a number,
    /// a deleted event, a penalty shootout and a workout.
    static func fullMatch() -> Match {
        let config = MatchConfig(
            homeName: "Lions", awayName: "Bears", competition: "County Cup", kickOff: kickOff,
            extraTimeEnabled: true, penaltiesEnabled: true)
        var match = Match(config: config, deviceID: deviceID, now: kickOff)
        var now = kickOff
        func tick() -> Date {
            now = now.addingTimeInterval(60)
            return now
        }
        match.log(.goal, side: .home, shirtNumber: 9, period: .firstHalf, minute: MatchMinute(base: 12), deviceID: deviceID, now: tick())
        match.log(.yellow, side: .away, shirtNumber: 4, period: .firstHalf, minute: MatchMinute(base: 45, added: 2), deviceID: deviceID, now: tick())
        match.log(.substitution, side: .away, playerOff: 4, playerOn: 15, period: .secondHalf, minute: MatchMinute(base: 60), deviceID: deviceID, now: tick())
        match.log(.goal, side: .away, period: .secondHalf, minute: MatchMinute(base: 70), deviceID: deviceID, now: tick())
        let deleted = match.log(.red, side: .home, shirtNumber: 3, period: .secondHalf, minute: MatchMinute(base: 80), deviceID: deviceID, now: tick())
        match.delete(deleted.id, deviceID: deviceID, now: tick())
        match.log(.goal, side: .home, shirtNumber: 10, period: .extraTimeFirst, minute: MatchMinute(base: 95), deviceID: deviceID, now: tick())
        match.log(.goal, side: .away, shirtNumber: 11, period: .extraTimeSecond, minute: MatchMinute(base: 118), deviceID: deviceID, now: tick())
        for (side, scored) in [(Side.home, true), (.away, true), (.home, true), (.away, false), (.home, true), (.away, true), (.home, true)] {
            match.logPenalty(side: side, shirtNumber: side == .home ? 7 : nil, scored: scored, deviceID: deviceID, now: tick())
        }
        match.setWorkout(
            WorkoutSummary(distanceMeters: 9_420, averageHeartRate: 151.4, durationSeconds: 6_125, savedToHealth: true, hasRoute: true),
            deviceID: deviceID, now: tick())
        match.finish(deviceID: deviceID, now: tick())
        return match
    }
}

@Suite struct ReportRenderingTests {
    @Test func pdfRendersForAFullMatch() {
        let data = ReportPDFRenderer.render(Fixtures.fullMatch(), timeZone: Fixtures.utc)
        #expect(data.count > 1_000)
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }

    @Test func pdfRendersForAMatchWithoutEvents() {
        let match = Match(config: MatchConfig(), deviceID: Fixtures.deviceID, now: Fixtures.kickOff)
        let data = ReportPDFRenderer.render(match, timeZone: Fixtures.utc)
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }

    @Test func longReportsGetMorePages() {
        var match = Match(config: MatchConfig(), deviceID: Fixtures.deviceID, now: Fixtures.kickOff)
        for minute in 1...90 {
            match.log(.yellow, side: .home, shirtNumber: minute, period: minute <= 45 ? .firstHalf : .secondHalf,
                      minute: MatchMinute(base: minute), deviceID: Fixtures.deviceID,
                      now: Fixtures.kickOff.addingTimeInterval(Double(minute)))
        }
        let short = ReportPDFRenderer.render(Fixtures.fullMatch(), timeZone: Fixtures.utc)
        let long = ReportPDFRenderer.render(match, timeZone: Fixtures.utc)
        #expect(Self.pageCount(long) > Self.pageCount(short))
    }

    @Test func shareFileName() {
        #expect(ReportFileName.make(match: Fixtures.fullMatch(), timeZone: Fixtures.utc) == "Lions v Bears 2026-11-10.pdf")
    }

    @Test func shareFileNameUsesTheGivenTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let late = Date(timeIntervalSince1970: 1_794_352_800) // 2026-11-10 23:20 UTC, 11 Nov in Tokyo
        #expect(ReportFileName.make(home: "Lions", away: "Bears", date: late, timeZone: Fixtures.utc) == "Lions v Bears 2026-11-10.pdf")
        #expect(ReportFileName.make(home: "Lions", away: "Bears", date: late, timeZone: tokyo) == "Lions v Bears 2026-11-11.pdf")
    }

    @Test func shareFileNameRemovesPathCharacters() {
        let name = ReportFileName.make(home: "A/B: United", away: "  ", date: Fixtures.kickOff, timeZone: Fixtures.utc)
        #expect(name == "A-B- United v Team 2026-11-10.pdf")
    }

    @Test func shareFileKeepsItsName() throws {
        let pdf = ReportPDF(fileName: "Lions v Bears 2026-11-10.pdf", data: Data("%PDF-1.7".utf8))
        let url = try pdf.writeTemporaryFile()
        #expect(url.lastPathComponent == "Lions v Bears 2026-11-10.pdf")
        #expect(try Data(contentsOf: url) == pdf.data)
    }

    // MARK: Layout

    @Test func layoutHasScoreEventsPenaltiesAndWorkout() throws {
        let match = Fixtures.fullMatch()
        let layout = ReportLayout(match: match, timeZone: Fixtures.utc, locale: Locale(identifier: "en_GB"))

        #expect(layout.title == "Lions vs Bears")
        #expect(layout.subtitle.hasPrefix("County Cup, "))
        #expect(layout.score == "Lions 2 - 2 Bears")
        #expect(layout.penalties == "Penalties 4 - 2")
        #expect(layout.sections.map(\.title) == ["1st half", "2nd half", "Extra time 1", "Extra time 2", "Penalties"])

        let first = layout.sections[0].rows
        #expect(first.map(\.lead) == ["12'", "45+2'"])
        #expect(first.map(\.text) == ["Goal, Lions, #9", "Yellow card, Bears, #4"])

        let second = layout.sections[1].rows.map(\.text)
        #expect(second == ["Substitution, Bears, off #4, on #15", "Goal, Bears, no number"])

        let penalties = layout.sections[4].rows
        #expect(penalties.count == 7)
        #expect(penalties[0].text == "Lions, #7, scored")
        #expect(penalties[3].text == "Bears, no number, missed")
        #expect(penalties.allSatisfy { $0.eventID == nil })

        #expect(layout.workout.map(\.text) == ["9.42 km", "151 bpm", "1:42:05", "Saved to Apple Health"])
    }

    @Test func eventRowsPointAtTheirEvents() {
        let match = Fixtures.fullMatch()
        let layout = ReportLayout(match: match, timeZone: Fixtures.utc)
        let ids = layout.sections.flatMap(\.rows).compactMap(\.eventID)
        #expect(ids == match.liveEvents.map(\.id))
        for row in layout.sections.flatMap(\.rows) {
            guard let id = row.eventID, let event = match.event(id) else { continue }
            #expect(row.lead == "\(event.minute)'")
        }
    }

    @Test func workoutNotSavedSaysSo() {
        let rows = ReportLayout.workoutRows(WorkoutSummary(savedToHealth: false))
        #expect(rows.map(\.text) == ["Not saved to Apple Health"])
    }

    private static func pageCount(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }
}
