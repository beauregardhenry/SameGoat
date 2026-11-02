import XCTest
@testable import HappyMama

@MainActor
final class WeeklyRecapTests: ServiceTestCase {
    private var now: Date { Date() }
    private var thisWeek: Date { WeeklyRecap.weekStart(for: now, calendar: calendar) }

    private func approve(points: Int, at date: Date, for member: Member? = nil) throws {
        let chore = try assign(points: points, to: member)
        try service.markComplete(chore, by: member ?? kid, note: nil, photo: nil)
        chore.completedAt = date
        try service.approve(chore, by: parent)
        kid.entryList.first { $0.choreID == chore.id }?.date = date
        (member ?? kid).entryList.first { $0.choreID == chore.id }?.date = date
    }

    private func weeksAgo(_ n: Int) -> Date {
        (calendar.date(byAdding: .weekOfYear, value: -n, to: thisWeek) ?? thisWeek).addingTimeInterval(3600)
    }

    func testThisWeeksPointsAndChores() throws {
        try approve(points: 10, at: weeksAgo(0))
        try approve(points: 5, at: weeksAgo(0))
        try approve(points: 7, at: weeksAgo(1))
        try service.giveBonus(3, reason: "Kind", to: kid, by: parent)

        let week = try XCTUnwrap(WeeklyRecap.summaries(for: [kid], now: now, calendar: calendar).first)
        XCTAssertEqual(week.name, "Sam")
        XCTAssertEqual(week.points, 18, "chores plus the bonus")
        XCTAssertEqual(week.choresDone, 2)
        XCTAssertEqual(week.history.count, WeeklyRecap.weeksShown)
        XCTAssertEqual(week.history.last?.start, thisWeek)
        XCTAssertEqual(week.history[WeeklyRecap.weeksShown - 2].points, 7)
    }

    func testSpendingDoesntCountAgainstTheWeek() throws {
        try approve(points: 10, at: weeksAgo(0))
        let treat = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 8, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: treat, by: kid)
        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        try service.decide(request, approve: true, by: parent)
        XCTAssertEqual(WeeklyRecap.summaries(for: [kid], now: now, calendar: calendar).first?.points, 10)
    }

    func testOlderThanEightWeeksIsLeftOut() throws {
        try approve(points: 9, at: weeksAgo(9))
        let week = try XCTUnwrap(WeeklyRecap.summaries(for: [kid], now: now, calendar: calendar).first)
        XCTAssertEqual(week.history.reduce(0) { $0 + $1.points }, 0)
    }

    func testHeadlines() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        XCTAssertEqual(WeeklyRecap.headline([]), "Add a kid to see their week.")
        XCTAssertEqual(WeeklyRecap.headline(WeeklyRecap.summaries(for: [kid, other], now: now, calendar: calendar)),
                       "A quiet week so far. There's still time!")
        try approve(points: 10, at: weeksAgo(0))
        try approve(points: 4, at: weeksAgo(0), for: other)
        XCTAssertEqual(WeeklyRecap.headline(WeeklyRecap.summaries(for: [kid, other], now: now, calendar: calendar)),
                       "Together: 14 points and 2 chores this week.")
        XCTAssertEqual(WeeklyRecap.headline(WeeklyRecap.summaries(for: [kid], now: now, calendar: calendar)),
                       "10 points and 1 chore this week.")
    }

    func testReminderIsSundayEvening() {
        XCTAssertEqual(WeeklyRecap.reminderTime.weekday, 1)
        XCTAssertEqual(WeeklyRecap.reminderTime.hour, 18)
    }
}
