import XCTest
@testable import HappyMama

@MainActor
final class VacationPauseTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

    private func pause(_ from: Int, _ until: Int) throws {
        try service.setPause(from: day(from), until: day(until), for: household, by: parent)
    }

    func testPauseCoversWholeDays() throws {
        try pause(0, 2)
        XCTAssertTrue(household.isPaused(on: day(0).addingTimeInterval(23 * 3600), calendar: calendar))
        XCTAssertTrue(household.isPaused(on: day(2), calendar: calendar))
        XCTAssertFalse(household.isPaused(on: day(3), calendar: calendar))
        XCTAssertFalse(household.isPaused(on: day(-1), calendar: calendar))
        XCTAssertNotNil(household.upcomingPause(calendar: calendar))
    }

    func testPauseRules() throws {
        assertThrowsServiceError(try service.setPause(from: day(0), until: day(2), for: household, by: kid))
        assertThrowsServiceError(try pause(3, 1))
        assertThrowsServiceError(try pause(-5, -2))
        XCTAssertNil(household.pausedFrom)

        try pause(0, 2)
        try service.setPause(from: nil, until: nil, for: household, by: parent)
        XCTAssertNil(household.upcomingPause(calendar: calendar))
    }

    func testChoresDueDuringThePauseNeverGoOverdue() throws {
        let duringTrip = try assign(title: "Trip", due: day(-2))
        let beforeTrip = try assign(title: "Before", due: day(-4))
        household.pausedFrom = day(-3)
        household.pausedUntil = day(-1)
        XCTAssertFalse(duringTrip.isOverdue(now: Date(), calendar: calendar))
        XCTAssertTrue(beforeTrip.isOverdue(now: Date(), calendar: calendar), "it was already late before the trip")

        household.pausedUntil = day(1)
        XCTAssertFalse(beforeTrip.isOverdue(now: Date(), calendar: calendar), "nothing is overdue mid-trip")
    }

    func testNoRemindersForChoresDueOnVacation() throws {
        _ = try assign(title: "Trip", due: day(2))
        _ = try assign(title: "After", due: day(5))
        try pause(1, 3)
        let titles = Notifier.dueReminders(household: household, me: kid, now: Date(), calendar: calendar).map(\.title)
        XCTAssertEqual(titles, ["Due today: After"])
    }

    func testRepeatingChoresSkipPastThePause() throws {
        var daily = RecurrenceRule()
        daily.kind = .daily
        let chore = try assign(title: "Feed cat", due: day(0), recurrence: daily)
        try pause(1, 4)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.dueDate, day(5))
    }

    /// A chore the kid turned in on that day.
    private func did(on offset: Int) throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        chore.completedAt = day(offset).addingTimeInterval(3600)
    }

    func testVacationDaysDontBreakTheStreak() throws {
        for offset in [-6, -5, -1, 0] { try did(on: offset) }
        XCTAssertEqual(kid.streak(calendar: calendar), 2)
        household.pausedFrom = day(-4)
        household.pausedUntil = day(-2)
        XCTAssertEqual(kid.streak(calendar: calendar), 4, "the trip days are skipped, not counted")
        XCTAssertEqual(Badges.bestStreak(for: kid, calendar: calendar), 4)
    }

    func testStreakHoldsWhileStillAway() throws {
        for offset in [-4, -3] { try did(on: offset) }
        household.pausedFrom = day(-2)
        household.pausedUntil = day(1)
        XCTAssertEqual(kid.streak(calendar: calendar), 2)
    }
}
