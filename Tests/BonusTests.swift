import XCTest
@testable import SameGoat

@MainActor
final class BonusTests: ServiceTestCase {
    func testParentGivesBonusWithAReason() throws {
        let entry = try service.giveBonus(5, reason: "  Helped your brother ", to: kid, by: parent)
        XCTAssertEqual(entry.kind, .bonus)
        XCTAssertEqual(entry.reason, "Helped your brother")
        XCTAssertEqual(kid.balance, 5)
        XCTAssertEqual(kid.available, 5)
    }

    func testBlankReasonBecomesBonus() throws {
        let entry = try service.giveBonus(3, reason: " ", to: kid, by: parent)
        XCTAssertEqual(entry.reason, "Bonus")
    }

    func testBonusRules() throws {
        assertThrowsServiceError(try service.giveBonus(5, reason: "", to: kid, by: kid))
        assertThrowsServiceError(try service.giveBonus(5, reason: "", to: parent, by: parent))
        assertThrowsServiceError(try service.giveBonus(0, reason: "", to: kid, by: parent))
        assertThrowsServiceError(try service.giveBonus(1001, reason: "", to: kid, by: parent))
        XCTAssertEqual(kid.balance, 0)
    }

    func testTwoBonusesAreNeverTreatedAsSyncDuplicates() throws {
        try service.giveBonus(5, reason: "Kind", to: kid, by: parent)
        try service.giveBonus(5, reason: "Kind", to: kid, by: parent)
        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(kid.balance, 10)
        XCTAssertEqual(kid.entryList.count, 2)
    }

    func testKidIsToldAboutARecentBonus() throws {
        let entry = try service.giveBonus(4, reason: "Extra effort", to: kid, by: parent)
        let events = Notifier().events(household: household, me: kid)
        XCTAssertEqual(events.map(\.title), ["Bonus! +4 points"])
        XCTAssertEqual(events.first?.body, "Extra effort")

        entry.date = Date().addingTimeInterval(-2 * 86_400)
        XCTAssertTrue(Notifier().events(household: household, me: kid).isEmpty, "old bonuses aren't news")
        XCTAssertTrue(Notifier().events(household: household, me: parent).isEmpty)
    }

    func testBonusCountsTowardTheGoal() throws {
        let movie = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 10, isActive: true, in: household, by: parent)
        try service.setGoal(movie, for: kid, by: kid)
        try service.giveBonus(5, reason: "Kind", to: kid, by: parent)
        XCTAssertEqual(kid.goalProgress, 0.5, accuracy: 0.001)
    }
}
