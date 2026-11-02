import XCTest
@testable import HappyMama

@MainActor
final class RoutineTests: ServiceTestCase {
    private func routine(_ steps: [String] = ["Bed", "Dressed", "Teeth"], daily: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Morning routine"
        draft.points = 4
        draft.steps = steps
        if daily {
            draft.recurrence.kind = .daily
            draft.dueDate = Date()
        }
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    func testStepsAreCleanedAndStored() throws {
        let chore = try routine(["  Bed ", "", "Teeth\nand floss"])
        XCTAssertEqual(chore.steps, ["Bed", "Teeth and floss"])
        XCTAssertTrue(chore.isRoutine)
        XCTAssertFalse(chore.allStepsDone)
    }

    func testKidMustTickEveryStepBeforeTurningItIn() throws {
        let chore = try routine()
        assertThrowsServiceError(try service.markComplete(chore, by: kid, note: nil, photo: nil))
        for index in 0..<3 { try service.toggleStep(index, of: chore, by: kid) }
        XCTAssertTrue(chore.allStepsDone)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        XCTAssertEqual(chore.status, .pendingReview)
    }

    func testTickingAgainUnticks() throws {
        let chore = try routine()
        try service.toggleStep(1, of: chore, by: kid)
        XCTAssertEqual(chore.doneSteps, [1])
        try service.toggleStep(1, of: chore, by: kid)
        XCTAssertEqual(chore.doneSteps, [])
        XCTAssertNil(chore.doneStepsRaw)
    }

    func testOnlyTheKidTicksAndOnlyBeforeTurningIn() throws {
        let chore = try routine(["One"])
        assertThrowsServiceError(try service.toggleStep(0, of: chore, by: parent))
        assertThrowsServiceError(try service.toggleStep(5, of: chore, by: kid))
        try service.toggleStep(0, of: chore, by: kid)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        assertThrowsServiceError(try service.toggleStep(0, of: chore, by: kid))
    }

    func testOrdinaryChoresHaveNoSteps() throws {
        let chore = try assign()
        XCTAssertFalse(chore.isRoutine)
        XCTAssertTrue(chore.allStepsDone, "nothing to tick")
    }

    func testEditingStepsClearsTicksButOtherEditsKeepThem() throws {
        let chore = try routine()
        try service.toggleStep(0, of: chore, by: kid)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Morning routine"
        draft.points = 6
        draft.steps = ["Bed", "Dressed", "Teeth"]
        try service.updateChore(chore, with: draft, assignee: kid, by: parent)
        XCTAssertEqual(chore.doneSteps, [0], "same steps, ticks stay")

        draft.steps = ["Bed", "Teeth"]
        try service.updateChore(chore, with: draft, assignee: kid, by: parent)
        XCTAssertEqual(chore.doneSteps, [], "the list changed, so start over")
    }

    func testTooManySteps() throws {
        assertThrowsServiceError(try routine((1...13).map { "Step \($0)" }))
    }

    func testRepeatingRoutineComesBackUnticked() throws {
        let chore = try routine(["One", "Two"], daily: true)
        try service.toggleStep(0, of: chore, by: kid)
        try service.toggleStep(1, of: chore, by: kid)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.steps, ["One", "Two"])
        XCTAssertEqual(next.doneSteps, [])
    }

    func testStaleTicksAreIgnored() throws {
        let chore = try routine(["One", "Two"])
        chore.doneStepsRaw = "0,7,x"
        XCTAssertEqual(chore.doneSteps, [0])
    }

    func testLibraryRoutinesCarryTheirSteps() throws {
        let morning = try XCTUnwrap(ChoreLibrary.templates.first { $0.title == "Morning routine" })
        XCTAssertEqual(ChoreLibrary.draft(from: morning).steps.count, 4)
        let created = try service.addFromLibrary([morning], assignees: [kid], takeTurns: false, in: household, by: parent)
        XCTAssertTrue(created[0].isRoutine)
    }
}
