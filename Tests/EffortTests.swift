import XCTest
@testable import SameGoat

@MainActor
final class EffortTests: ServiceTestCase {
    func testSuggestedPointsFromTimeAndDifficulty() {
        XCTAssertNil(Effort.suggestedPoints(minutes: nil, difficulty: nil, rate: 1))
        XCTAssertEqual(Effort.suggestedPoints(minutes: 5, difficulty: .easy, rate: 1), 1)
        XCTAssertEqual(Effort.suggestedPoints(minutes: 15, difficulty: .medium, rate: 1), 5)   // 3 × 1.5 = 4.5, rounded
        XCTAssertEqual(Effort.suggestedPoints(minutes: 30, difficulty: .hard, rate: 1), 12)
        XCTAssertEqual(Effort.suggestedPoints(minutes: 12, difficulty: .easy, rate: 1), 3, "partial blocks round up")
        XCTAssertEqual(Effort.suggestedPoints(minutes: 15, difficulty: .hard, rate: 2), 12)
    }

    func testEitherHalfAloneStillSuggests() {
        XCTAssertEqual(Effort.suggestedPoints(minutes: 20, difficulty: nil, rate: 1), 6, "medium is assumed")
        XCTAssertEqual(Effort.suggestedPoints(minutes: nil, difficulty: .hard, rate: 1), 4, "ten minutes is assumed")
    }

    func testLabels() {
        XCTAssertEqual(Effort.label(minutes: 15, difficulty: .hard), "15 min · Hard")
        XCTAssertEqual(Effort.label(minutes: 15, difficulty: nil), "15 min")
        XCTAssertEqual(Effort.label(minutes: nil, difficulty: .easy), "Easy")
        XCTAssertNil(Effort.label(minutes: nil, difficulty: nil))
    }

    private func draft(minutes: Int?, difficulty: Difficulty?, daily: Bool = false) -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Vacuum"
        draft.minutes = minutes
        draft.difficulty = difficulty
        if daily {
            draft.recurrence.kind = .daily
            draft.dueDate = Date()
        }
        return draft
    }

    func testEffortIsStoredEditedAndCarriedToTheNextCopy() throws {
        let chore = try service.createChores(draft(minutes: 20, difficulty: .medium, daily: true),
                                             assignees: [kid], in: household, by: parent)[0]
        XCTAssertEqual(chore.minutes, 20)
        XCTAssertEqual(chore.difficulty, .medium)
        XCTAssertEqual(chore.effortLabel, "20 min · Medium")

        try service.updateChore(chore, with: draft(minutes: 30, difficulty: .hard, daily: true), assignee: kid, by: parent)
        XCTAssertEqual(chore.minutes, 30)
        XCTAssertEqual(chore.difficulty, .hard)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.minutes, 30)
        XCTAssertEqual(next.difficulty, .hard)

        try service.updateChore(next, with: draft(minutes: nil, difficulty: nil, daily: true), assignee: kid, by: parent)
        XCTAssertNil(next.minutes)
        XCTAssertNil(next.difficultyRaw)
    }

    func testTimeLimits() throws {
        assertThrowsServiceError(try service.createChores(draft(minutes: 0, difficulty: nil), assignees: [kid], in: household, by: parent))
        assertThrowsServiceError(try service.createChores(draft(minutes: 601, difficulty: nil), assignees: [kid], in: household, by: parent))
        let chore = try assign()
        chore.minutes = 9_999
        XCTAssertEqual(chore.minutes, 600)
        chore.difficultyRaw = "impossible"
        XCTAssertNil(chore.difficulty)
    }

    func testRateSetting() throws {
        XCTAssertEqual(household.effortRate, 1)
        try service.setEffortRate(3, for: household, by: parent)
        XCTAssertEqual(household.effortRate, 3)
        assertThrowsServiceError(try service.setEffortRate(3, for: household, by: kid))
        assertThrowsServiceError(try service.setEffortRate(0, for: household, by: parent))
        assertThrowsServiceError(try service.setEffortRate(21, for: household, by: parent))
    }

    func testOpenMinutesCountTheComingWeek() throws {
        let today = calendar.startOfDay(for: Date())
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today) ?? today }
        for (minutes, due) in [(20, day(1)), (10, nil as Date?), (30, day(10))] {
            var d = draft(minutes: minutes, difficulty: nil)
            d.dueDate = due
            try service.createChores(d, assignees: [kid], in: household, by: parent)
        }
        let done = try service.createChores(draft(minutes: 45, difficulty: nil), assignees: [kid], in: household, by: parent)[0]
        try service.markComplete(done, by: kid, note: nil, photo: nil)

        XCTAssertEqual(Effort.openMinutes(for: kid, calendar: calendar), 30, "next week's 30 and the finished 45 don't count")
    }

    func testRecapAddsUpThisWeeksMinutes() throws {
        let chore = try service.createChores(draft(minutes: 25, difficulty: .easy), assignees: [kid], in: household, by: parent)[0]
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        XCTAssertEqual(WeeklyRecap.summaries(for: [kid], calendar: calendar).first?.minutes, 25)
    }

    func testLibraryIdeasCarryEffort() throws {
        let lawn = try XCTUnwrap(ChoreLibrary.templates.first { $0.title == "Mow the lawn" })
        XCTAssertEqual(ChoreLibrary.draft(from: lawn).minutes, 60)
        XCTAssertEqual(ChoreLibrary.draft(from: lawn).difficulty, .hard)
        XCTAssertTrue(ChoreLibrary.templates.allSatisfy { $0.minutes != nil && $0.difficulty != nil })
    }
}
