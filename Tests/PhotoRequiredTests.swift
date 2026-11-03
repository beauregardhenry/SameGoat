import XCTest
@testable import SameGoat

@MainActor
final class PhotoRequiredTests: ServiceTestCase {
    private let photo = Data([0xFF, 0xD8, 0xFF])

    private func roomChore(daily: Bool = false) throws -> Chore {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Clean your room"
        draft.photoRequired = true
        if daily {
            draft.recurrence.kind = .daily
            draft.dueDate = Date()
        }
        return try service.createChores(draft, assignees: [kid], in: household, by: parent)[0]
    }

    func testNeedsAPhotoToTurnIn() throws {
        let chore = try roomChore()
        XCTAssertThrowsError(try service.markComplete(chore, by: kid, note: "done", photo: nil)) { error in
            XCTAssertEqual(error.localizedDescription, "Add a photo to show it's done.")
        }
        XCTAssertEqual(chore.status, .todo)
        try service.markComplete(chore, by: kid, note: nil, photo: photo)
        XCTAssertEqual(chore.photo, photo)
    }

    func testOrdinaryChoresDontNeedOne() throws {
        let chore = try assign()
        XCTAssertFalse(chore.photoRequired)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
    }

    func testEditingAndRepeatingKeepTheSetting() throws {
        let chore = try roomChore(daily: true)
        try service.markComplete(chore, by: kid, note: nil, photo: photo)
        try service.approve(chore, by: parent)
        let next = try XCTUnwrap((household.chores as? Set<Chore>)?.first { $0.sourceChoreID == chore.id })
        XCTAssertTrue(next.photoRequired)

        var draft = HouseholdService.ChoreDraft()
        draft.title = "Clean your room"
        draft.dueDate = Date()
        draft.recurrence.kind = .daily
        try service.updateChore(next, with: draft, assignee: kid, by: parent)
        XCTAssertFalse(next.photoRequired)
    }

    func testSendingBackClearsThePhotoSoANewOneIsNeeded() throws {
        let chore = try roomChore()
        try service.markComplete(chore, by: kid, note: nil, photo: photo)
        try service.reject(chore, by: parent, note: "Under the bed too")
        XCTAssertNil(chore.photo)
        assertThrowsServiceError(try service.markComplete(chore, by: kid, note: nil, photo: nil))
    }
}
