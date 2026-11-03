import XCTest
@testable import SameGoat

@MainActor
final class QuickWinTests: ServiceTestCase {
    private func draft(_ title: String = "Dishes") -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = title
        return draft
    }

    func testHelpsTipsSkillAndFlagsAreStoredAndCarried() throws {
        var d = draft()
        d.whyItHelps = "  Clean dishes for dinner. "
        d.tips = "Rinse first."
        d.skill = 4
        d.stretch = true
        d.recurrence.kind = .daily
        d.dueDate = Date()
        let chore = try service.createChores(d, assignees: [kid], in: household, by: parent)[0]
        XCTAssertEqual(chore.whyItHelps, "Clean dishes for dinner.")
        XCTAssertEqual(chore.tips, "Rinse first.")
        XCTAssertEqual(chore.skill, 4)
        XCTAssertTrue(chore.stretch)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.whyItHelps, "Clean dishes for dinner.")
        XCTAssertEqual(next.skill, 4)
        XCTAssertTrue(next.stretch)

        var cleared = draft()
        cleared.recurrence.kind = .daily
        cleared.dueDate = Date()
        try service.updateChore(next, with: cleared, assignee: kid, by: parent)
        XCTAssertNil(next.whyItHelps)
        XCTAssertNil(next.tips)
        XCTAssertNil(next.skill)
        XCTAssertFalse(next.stretch)
    }

    func testExtraCreditIsNeverOverdueOrNagged() throws {
        var d = draft()
        d.extraCredit = true
        d.dueDate = calendar.date(byAdding: .day, value: -3, to: Date())
        let chore = try service.createChores(d, assignees: [kid], in: household, by: parent)[0]
        XCTAssertFalse(chore.isOverdue(calendar: calendar))
        var soon = draft("Later")
        soon.extraCredit = true
        soon.dueDate = calendar.date(byAdding: .day, value: 2, to: Date())
        try service.createChores(soon, assignees: [kid], in: household, by: parent)
        XCTAssertTrue(Notifier.dueReminders(household: household, me: kid, calendar: calendar).isEmpty)
        XCTAssertEqual(AssistantReplies.summary(household: household, me: kid, calendar: calendar), "You're all done for today!")
        XCTAssertTrue(WidgetSnapshot(household: household, me: kid, calendar: calendar).kids[0].open.isEmpty)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertEqual(kid.balance, 10, "it still earns points")
    }

    func testDueAnyDayThatWeek() throws {
        var d = draft()
        d.dueWithinWeek = true
        d.dueDate = Date()
        d.dueTime = 9 * 60
        let chore = try service.createChores(d, assignees: [kid], in: household, by: parent)[0]
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        XCTAssertEqual(chore.dueDate, calendar.date(byAdding: .day, value: 6, to: week.start))
        XCTAssertNil(chore.dueTime, "a week has no time of day")
        XCTAssertTrue(chore.dueWithinWeek)
        XCTAssertFalse(chore.isOverdue(now: Date(), calendar: calendar))
    }

    func testSkillAddsToSuggestedPoints() {
        XCTAssertEqual(Effort.suggestedPoints(minutes: 20, difficulty: .medium, rate: 1), 6)
        XCTAssertEqual(Effort.suggestedPoints(minutes: 20, difficulty: .medium, rate: 1, skill: 1), 6)
        XCTAssertEqual(Effort.suggestedPoints(minutes: 20, difficulty: .medium, rate: 1, skill: 5), 8)   // 6 × 1.4
    }

    func testStarsForTheCharacterCard() {
        XCTAssertTrue(Effort.stars(minutes: nil, difficulty: nil, skill: nil).isEmpty)
        let room = Effort.stars(minutes: 60, difficulty: .easy, skill: 4)
        XCTAssertEqual(room, Effort.Stars(time: 5, difficulty: 1, thinking: 4))
        XCTAssertEqual(Effort.stars(minutes: 5, difficulty: .medium, skill: nil).time, 1)
        XCTAssertEqual(Effort.stars(minutes: 20, difficulty: .hard, skill: nil), Effort.Stars(time: 3, difficulty: 5, thinking: nil))
    }

    func testLevelsGrowWithPractice() throws {
        func approveDishes() throws -> Chore {
            let chore = try assign(title: "Dishes")
            try service.markComplete(chore, by: kid, note: nil, photo: nil)
            try service.approve(chore, by: parent)
            return chore
        }
        let open = try assign(title: "dishes")
        XCTAssertEqual(ChoreLevel.of(open), .new)
        for _ in 0..<3 { _ = try approveDishes() }
        XCTAssertEqual(ChoreLevel.timesDone(open), 3, "names match regardless of case")
        XCTAssertEqual(ChoreLevel.of(open), .learning)
        for _ in 0..<7 { _ = try approveDishes() }
        XCTAssertEqual(ChoreLevel.of(open), .pro)
        XCTAssertEqual(ChoreLevel.pro.title, "Pro")

        var pool = draft("Pool")
        pool.upForGrabs = true
        XCTAssertNil(ChoreLevel.of(try service.createChores(pool, assignees: [], in: household, by: parent)[0]))
    }

    func testLibraryIdeasExplainThemselves() throws {
        XCTAssertTrue(ChoreLibrary.templates.allSatisfy { $0.helps != nil && $0.tips != nil })
        let trash = try XCTUnwrap(ChoreLibrary.templates.first { $0.title == "Take out the trash" })
        XCTAssertFalse(ChoreLibrary.draft(from: trash).whyItHelps.isEmpty)
    }
}
