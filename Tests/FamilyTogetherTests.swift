import XCTest
@testable import HappyMama

@MainActor
final class GrownUpChoreTests: ServiceTestCase {
    private func grownUpChore(_ title: String = "Insurance call", points: Int = 10, daily: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = title
        draft.points = points
        draft.dueDate = Date()
        if daily { draft.recurrence.kind = .daily }
        return try service.createChores(draft, assignees: [parent], in: household, by: parent)[0]
    }

    func testGrownUpsCanHaveChoresWithNoPoints() throws {
        let chore = try grownUpChore(points: 10)
        XCTAssertEqual(chore.assignee, parent)
        XCTAssertEqual(chore.points, 0)
        XCTAssertTrue(chore.isFamilyJob)
    }

    func testAGrownUpTicksOffTheirOwnChoreWithoutReview() throws {
        let chore = try grownUpChore(daily: true)
        try service.markComplete(chore, by: parent, note: nil, photo: nil)
        XCTAssertEqual(chore.status, .approved)
        XCTAssertEqual(parent.balance, 0)
        XCTAssertTrue(parent.entryList.isEmpty)
        XCTAssertTrue(Notifier().events(household: household, me: parent).isEmpty, "nothing to review")
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.assignee, parent)
        assertThrowsServiceError(try service.markComplete(chore, by: parent, note: nil, photo: nil))
    }

    func testOnlyThatGrownUpOrNobodyElse() throws {
        let papa = try service.addMember(name: "Papa", role: .parent, emoji: "🌷", to: household, by: parent)
        let chore = try grownUpChore()
        assertThrowsServiceError(try service.markComplete(chore, by: papa, note: nil, photo: nil))
        assertThrowsServiceError(try service.markComplete(chore, by: kid, note: nil, photo: nil))
    }

    func testTakingTurnsStaysForKids() throws {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Trash"
        draft.takeTurns = true
        draft.recurrence.kind = .weekly
        draft.dueDate = Date()
        assertThrowsServiceError(try service.createChores(draft, assignees: [kid, parent], in: household, by: parent))
    }
}

@MainActor
final class SpoonsTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today) ?? today }

    private func chore(_ title: String, due: Date?, difficulty: Difficulty? = nil, spoons: Int? = nil, extra: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = title
        draft.dueDate = due
        draft.difficulty = difficulty
        draft.spoons = spoons
        draft.extraCredit = extra
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    func testSpoonsComeFromDifficultyUnlessSet() throws {
        XCTAssertEqual(try chore("A", due: nil, difficulty: .easy).spoons, 1)
        XCTAssertEqual(try chore("B", due: nil).spoons, 2)
        XCTAssertEqual(try chore("C", due: nil, difficulty: .hard).spoons, 3)
        XCTAssertEqual(try chore("D", due: nil, difficulty: .hard, spoons: 1).spoons, 1)
    }

    func testPlanPutsDeadlinesFirstThenWhatFits() throws {
        _ = try chore("Due today, hard", due: day(0), difficulty: .hard)
        _ = try chore("Late", due: day(-1), difficulty: .easy)
        _ = try chore("Easy later", due: day(3), difficulty: .easy)
        _ = try chore("Hard later", due: day(3), difficulty: .hard)
        _ = try chore("Optional", due: day(0), difficulty: .easy, extra: true)

        let low = Spoons.plan(for: kid, spoons: 1, calendar: calendar)
        XCTAssertEqual(low.mustDo.map(\.displayTitle), ["Late", "Due today, hard"])
        XCTAssertEqual(low.fits.map(\.displayTitle), ["Optional", "Easy later"])
        XCTAssertEqual(low.later.map(\.displayTitle), ["Hard later"])

        let high = Spoons.plan(for: kid, spoons: 3, calendar: calendar)
        XCTAssertTrue(high.later.isEmpty)
    }

    func testChoresOnHoldForAProjectStayOutOfThePlan() throws {
        _ = try chore("Dishes", due: day(0))
        _ = try service.startProject(.init(preset: ProjectLibrary.presets[0], dueDate: day(1)), sharedWith: [kid],
                                     in: household, by: parent)
        let plan = Spoons.plan(for: kid, spoons: 3, calendar: calendar)
        XCTAssertFalse((plan.mustDo + plan.fits + plan.later).contains { $0.displayTitle == "Dishes" })
    }

    func testResetPassPushesOneChoreToTomorrowOnceADay() throws {
        try service.setFeature(.energy, on: true, for: household, by: parent)
        let first = try chore("Bed", due: day(0))
        let second = try chore("Room", due: day(0))
        try service.useResetPass(on: first, by: kid)
        XCTAssertEqual(first.dueDate, day(1))
        XCTAssertNotNil(kid.resetUsedOn)
        assertThrowsServiceError(try service.useResetPass(on: second, by: kid))

        let tomorrowNoon = day(1).addingTimeInterval(12 * 3600)
        try service.useResetPass(on: first, by: kid, now: tomorrowNoon)
        XCTAssertEqual(first.dueDate, day(2), "a new day brings a new pass")
    }

    func testResetPassRules() throws {
        let off = try chore("Off", due: day(0))
        assertThrowsServiceError(try service.useResetPass(on: off, by: kid))   // energy isn't switched on
        try service.setFeature(.energy, on: true, for: household, by: parent)
        let later = try chore("Later", due: day(3))
        assertThrowsServiceError(try service.useResetPass(on: later, by: kid))
        let undated = try chore("Whenever", due: nil)
        assertThrowsServiceError(try service.useResetPass(on: undated, by: kid))
        let today = try chore("Today", due: day(0))
        assertThrowsServiceError(try service.useResetPass(on: today, by: parent))
    }
}
