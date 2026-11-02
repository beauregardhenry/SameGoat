import XCTest
@testable import HappyMama

@MainActor
final class AllowanceTests: ServiceTestCase {
    private let us = Locale(identifier: "en_US")

    private func earn(_ points: Int) throws {
        try service.giveBonus(points, reason: "Earned", to: kid, by: parent)
    }

    func testOffByDefault() {
        XCTAssertFalse(household.allowanceOn)
        XCTAssertNil(household.money(for: 50))
        XCTAssertNil(household.moneyText(for: 50))
    }

    func testRateConvertsPointsToMoney() throws {
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        XCTAssertTrue(household.allowanceOn)
        XCTAssertEqual(household.money(for: 25), Decimal(string: "2.5"))
        XCTAssertEqual(household.moneyText(for: 25, locale: us), "$2.50")

        try service.setAllowance(rate: 4, currencyCode: "EUR", for: household, by: parent)
        XCTAssertEqual(household.money(for: 10), Decimal(string: "2.5"))
        XCTAssertEqual(household.currencyCode, "EUR")

        try service.setAllowance(rate: nil, currencyCode: "EUR", for: household, by: parent)
        XCTAssertFalse(household.allowanceOn)
    }

    func testAllowanceRules() throws {
        assertThrowsServiceError(try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: kid))
        assertThrowsServiceError(try service.setAllowance(rate: 0, currencyCode: "USD", for: household, by: parent))
        assertThrowsServiceError(try service.setAllowance(rate: 1001, currencyCode: "USD", for: household, by: parent))
        XCTAssertFalse(household.allowanceOn)
    }

    func testPayOutSpendsThePointsAndSaysHowMuch() throws {
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        try earn(50)
        let entry = try service.payOut(30, to: kid, by: parent)
        XCTAssertEqual(entry.kind, .payout)
        XCTAssertEqual(entry.amount, -30)
        XCTAssertTrue(entry.reason?.hasPrefix("Paid ") == true)
        XCTAssertEqual(kid.balance, 20)
    }

    func testPayOutRules() throws {
        try earn(20)
        assertThrowsServiceError(try service.payOut(10, to: kid, by: parent))   // allowance off
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        assertThrowsServiceError(try service.payOut(10, to: kid, by: kid))
        assertThrowsServiceError(try service.payOut(10, to: parent, by: parent))
        assertThrowsServiceError(try service.payOut(0, to: kid, by: parent))
        assertThrowsServiceError(try service.payOut(21, to: kid, by: parent))

        let treat = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 15, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: treat, by: kid)
        assertThrowsServiceError(try service.payOut(10, to: kid, by: parent))  // 15 are on hold
        try service.payOut(5, to: kid, by: parent)
        XCTAssertEqual(kid.balance, 15)
    }

    func testKidIsToldAndSiriSaysTheMoney() throws {
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        try earn(40)
        try service.payOut(20, to: kid, by: parent)
        let titles = Notifier().events(household: household, me: kid).map(\.title)
        XCTAssertTrue(titles.contains { $0.hasPrefix("Paid ") })
        XCTAssertTrue(AssistantReplies.points(household: household, me: kid).contains("That's"))
    }

    func testPayoutsAreNeverMergedAsSyncDuplicates() throws {
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        try earn(40)
        try service.payOut(10, to: kid, by: parent)
        try service.payOut(10, to: kid, by: parent)
        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual(kid.balance, 20)
    }
}
