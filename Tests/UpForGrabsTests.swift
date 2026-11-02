import XCTest
@testable import HappyMama

@MainActor
final class UpForGrabsTests: ServiceTestCase {
    private var pip: Member!

    override func setUp() async throws {
        try await super.setUp()
        pip = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
    }

    private func grabs(points: Int = 5, daily: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Unload groceries"
        draft.points = points
        draft.upForGrabs = true
        if daily {
            draft.recurrence.kind = .daily
            draft.dueDate = Date()
        }
        let created = try service.createChores(draft, assignees: [kid, pip], in: household, by: parent)
        XCTAssertEqual(created.count, 1, "one chore in the pool, not a copy each")
        return created[0]
    }

    func testStartsUnclaimedInThePool() throws {
        let chore = try grabs()
        XCTAssertTrue(chore.upForGrabs)
        XCTAssertNil(chore.assignee)
        XCTAssertTrue(chore.isUnclaimed)
    }

    func testWhoeverFinishesItGetsThePoints() throws {
        let chore = try grabs(points: 5)
        try service.markComplete(chore, by: pip, note: nil, photo: nil)
        XCTAssertEqual(chore.assignee, pip)
        try service.approve(chore, by: parent)
        XCTAssertEqual(pip.balance, 5)
        XCTAssertEqual(kid.balance, 0)
    }

    func testClaimingReservesItAndReleasingPutsItBack() throws {
        let chore = try grabs()
        try service.claim(chore, by: kid)
        XCTAssertEqual(chore.assignee, kid)
        assertThrowsServiceError(try service.claim(chore, by: pip))
        assertThrowsServiceError(try service.markComplete(chore, by: pip, note: nil, photo: nil))
        assertThrowsServiceError(try service.release(chore, by: pip))

        try service.release(chore, by: kid)
        XCTAssertTrue(chore.isUnclaimed)
        try service.claim(chore, by: pip)
        try service.release(chore, by: parent)
        XCTAssertTrue(chore.isUnclaimed, "a parent can put it back too")
    }

    func testParentsCantClaimAndOnlyPoolChoresRelease() throws {
        let chore = try grabs()
        assertThrowsServiceError(try service.claim(chore, by: parent))
        assertThrowsServiceError(try service.release(chore, by: parent))   // not claimed
        assertThrowsServiceError(try service.release(try assign(), by: parent))
    }

    func testRepeatingPoolChoreComesBackUnclaimed() throws {
        let chore = try grabs(daily: true)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertTrue(next.isUnclaimed)
    }

    func testEditingKeepsAClaimButConvertingEmptiesIt() throws {
        let chore = try grabs()
        try service.claim(chore, by: kid)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Unload all the groceries"
        draft.upForGrabs = true
        try service.updateChore(chore, with: draft, assignees: [], by: parent)
        XCTAssertEqual(chore.assignee, kid)
        XCTAssertEqual(chore.title, "Unload all the groceries")

        let normal = try assign()
        try service.updateChore(normal, with: draft, assignees: [], by: parent)
        XCTAssertTrue(normal.isUnclaimed)

        draft.upForGrabs = false
        try service.updateChore(normal, with: draft, assignees: [pip], by: parent)
        XCTAssertFalse(normal.upForGrabs)
        XCTAssertEqual(normal.assignee, pip)
    }

    func testRemovingAKidPutsTheirClaimBack() throws {
        let chore = try grabs()
        try service.claim(chore, by: kid)
        try service.removeMember(kid, by: parent)
        XCTAssertFalse(chore.isDeleted)
        XCTAssertTrue(chore.isUnclaimed)
    }

    func testKidsHearAboutNewPoolChoresAndSiriOffersThem() throws {
        let chore = try grabs(points: 5)
        XCTAssertTrue(Notifier().events(household: household, me: kid).map(\.title).contains("Up for grabs: Unload groceries"))
        XCTAssertTrue(AssistantReplies.openChores(for: pip).contains(chore))
        try service.claim(chore, by: kid)
        XCTAssertFalse(AssistantReplies.openChores(for: pip).contains(chore))
    }
}

@MainActor
final class TurnsAndNudgeTests: ServiceTestCase {
    func testSkipTurnPassesToTheNextKid() throws {
        let pip = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Trash"
        draft.recurrence.kind = .weekly
        draft.dueDate = Date()
        draft.takeTurns = true
        let chore = try service.createChores(draft, assignees: [kid, pip], in: household, by: parent)[0]
        try service.skipTurn(chore, by: parent)
        XCTAssertEqual(chore.assignee, pip)
        assertThrowsServiceError(try service.skipTurn(chore, by: kid))
        assertThrowsServiceError(try service.skipTurn(try assign(), by: parent))
    }

    func testNudgeRemindsTheKidOnceInAWhile() throws {
        let chore = try assign(title: "Dishes")
        chore.emoji = "🍽️"
        let now = Date()
        try service.nudge(chore, by: parent, now: now)
        XCTAssertEqual(chore.nudgedByName, "Mama")
        let event = try XCTUnwrap(Notifier().events(household: household, me: kid).first { $0.title.hasPrefix("Reminder") })
        XCTAssertEqual(event.title, "Reminder from Mama")
        XCTAssertEqual(event.body, "🍽️ Dishes")

        assertThrowsServiceError(try service.nudge(chore, by: parent, now: now.addingTimeInterval(60)))
        try service.nudge(chore, by: parent, now: now.addingTimeInterval(HouseholdService.nudgeInterval + 1))
        assertThrowsServiceError(try service.nudge(chore, by: kid))
    }

    func testNoNudgesForFinishedOrPoolChores() throws {
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        assertThrowsServiceError(try service.nudge(chore, by: parent))
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Pool"
        draft.upForGrabs = true
        let pool = try service.createChores(draft, assignees: [], in: household, by: parent)[0]
        assertThrowsServiceError(try service.nudge(pool, by: parent))
    }
}

@MainActor
final class ChoreDetailsTests: ServiceTestCase {
    func testTimeOfDayEmojiAndFamilyJobsAreStoredAndCarried() throws {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Shoes away"
        draft.points = 0
        draft.emoji = " 👟 "
        draft.timeOfDay = .afternoon
        draft.recurrence.kind = .daily
        draft.dueDate = Date()
        let chore = try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
        XCTAssertEqual(chore.emoji, "👟")
        XCTAssertEqual(chore.timeOfDay, .afternoon)
        XCTAssertTrue(chore.isFamilyJob)

        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertEqual(next.emoji, "👟")
        XCTAssertEqual(next.timeOfDay, .afternoon)

        draft.emoji = "  "
        draft.timeOfDay = nil
        try service.updateChore(next, with: draft, assignee: kid, by: parent)
        XCTAssertNil(next.emoji)
        XCTAssertNil(next.timeOfDayRaw)
        XCTAssertEqual(TimeOfDay.allCases.map(\.title), ["Morning", "Afternoon", "Evening"])
    }

    func testLibraryIdeasHavePictures() {
        XCTAssertTrue(ChoreLibrary.templates.allSatisfy { $0.emoji != nil })
        let bed = ChoreLibrary.templates.first { $0.title == "Make your bed" }
        XCTAssertEqual(bed.map { ChoreLibrary.draft(from: $0).timeOfDay }, .morning)
    }
}
