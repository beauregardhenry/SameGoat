import XCTest
@testable import SameGoat

@MainActor
final class ChoiceMenuTests: ServiceTestCase {
    private func templates(_ titles: [String]) throws -> [ChoreLibrary.Template] {
        try titles.map { title in try XCTUnwrap(ChoreLibrary.templates.first { $0.title == title && $0.age == .kids }) }
    }

    private func menu(pick: Int = 2) throws -> [Chore] {
        try service.addChoiceMenu(try templates(["Set the table", "Tidy your room", "Fold the laundry", "Take out the trash"]),
                                  pick: pick, for: [kid], in: household, by: parent)
    }

    func testMenuOffersOptionsThatArentOwedYet() throws {
        let options = try menu()
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(Set(options.compactMap(\.menuID)).count, 1)
        XCTAssertTrue(options.allSatisfy { $0.isMenuOption && $0.dueWithinWeek && !$0.recurrence.isRepeating })
        options[0].dueDate = calendar.date(byAdding: .day, value: -3, to: Date())
        XCTAssertFalse(options[0].isOverdue(calendar: calendar), "an option isn't owed until it's picked")
        XCTAssertTrue(Spoons.plan(for: kid, spoons: 3, calendar: calendar).fits.isEmpty)
    }

    func testPickingEnoughClearsTheRest() throws {
        let options = try menu(pick: 2)
        try service.pick(options[0], by: kid)
        XCTAssertEqual(ChoiceMenu.pickedCount(like: options[0]), 1)
        XCTAssertEqual(ChoiceMenu.options(like: options[0]).count, 4)
        try service.pick(options[1], by: kid)
        let left = ChoiceMenu.options(like: options[0])
        XCTAssertEqual(left.count, 2)
        XCTAssertTrue(left.allSatisfy(\.menuPicked))
    }

    func testChangingYourMindBeforeTheChoiceIsMade() throws {
        let options = try menu(pick: 2)
        try service.pick(options[0], by: kid)
        try service.unpick(options[0], by: kid)
        XCTAssertTrue(options[0].isMenuOption)
        try service.pick(options[0], by: kid)
        try service.pick(options[1], by: kid)
        assertThrowsServiceError(try service.unpick(options[0], by: kid))
        assertThrowsServiceError(try service.pick(options[0], by: kid))
    }

    func testDoingAnOptionChoosesIt() throws {
        let options = try menu(pick: 1)
        try service.markComplete(options[2], by: kid, note: nil, photo: nil)
        XCTAssertTrue(options[2].menuPicked)
        XCTAssertEqual(ChoiceMenu.options(like: options[2]).count, 1)
    }

    func testSpotsAKidWhoAlwaysGoesEasy() throws {
        XCTAssertFalse(ChoiceMenu.prefersEasy(kid))
        for _ in 0..<3 {
            let options = try menu(pick: 1)
            let easiest = try XCTUnwrap(options.min { ChoiceMenu.rank($0.difficulty) < ChoiceMenu.rank($1.difficulty) })
            try service.pick(easiest, by: kid)
            XCTAssertTrue(easiest.menuEasiest)
        }
        XCTAssertTrue(ChoiceMenu.prefersEasy(kid))

        let options = try menu(pick: 1)
        let hardest = try XCTUnwrap(options.max { ChoiceMenu.rank($0.difficulty) < ChoiceMenu.rank($1.difficulty) })
        try service.pick(hardest, by: kid)
        XCTAssertFalse(hardest.menuEasiest)
        XCTAssertFalse(ChoiceMenu.prefersEasy(kid))
    }

    func testMenuRules() throws {
        let two = try templates(["Set the table", "Tidy your room"])
        assertThrowsServiceError(try service.addChoiceMenu(Array(two.prefix(1)), pick: 1, for: [kid], in: household, by: parent))
        assertThrowsServiceError(try service.addChoiceMenu(two, pick: 2, for: [kid], in: household, by: parent))
        assertThrowsServiceError(try service.addChoiceMenu(two, pick: 1, for: [], in: household, by: parent))
        assertThrowsServiceError(try service.addChoiceMenu(two, pick: 1, for: [parent], in: household, by: parent))
        assertThrowsServiceError(try service.addChoiceMenu(two, pick: 1, for: [kid], in: household, by: kid))
        let options = try menu()
        assertThrowsServiceError(try service.pick(options[0], by: parent))
    }

    func testBigPictureIsAParentSettingForKids() throws {
        try service.setBigPicture(true, for: kid, by: parent)
        XCTAssertTrue(kid.bigPicture)
        assertThrowsServiceError(try service.setBigPicture(false, for: kid, by: kid))
        assertThrowsServiceError(try service.setBigPicture(true, for: parent, by: parent))
    }
}
