import XCTest
import UserNotifications
@testable import SameGoat

/// What each person is told, and only once: the events a kid or parent should hear about, and the
/// memory of what they've already been told.
@MainActor
final class NotifierDeliveryTests: ServiceTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var notifier: Notifier!

    override func setUp() async throws {
        try await super.setUp()
        suite = "NotifierDeliveryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        notifier = Notifier(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func titles(for member: Member) -> [String] {
        notifier.events(household: household, me: member).map(\.title)
    }

    // MARK: What a kid hears about

    func testKidsHearAboutChoresUpForGrabs() throws {
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Feed the cat"
        draft.points = 6
        draft.upForGrabs = true
        let chore = try XCTUnwrap(service.createChores(draft, assignees: [], in: household, by: parent).first)

        let events = notifier.events(household: household, me: kid)
        XCTAssertEqual(events.map(\.title), ["Up for grabs: Feed the cat"])
        XCTAssertEqual(events.first?.body, "First to do it gets 6 points.")
        XCTAssertNil(events.first?.category, "nothing to approve, so no buttons")

        try service.claim(chore, by: kid)
        XCTAssertFalse(titles(for: kid).contains("Up for grabs: Feed the cat"), "once it's claimed it's no longer up for grabs")
    }

    func testAReminderFromAParentReachesTheKidAndKeysOnWhenItWasSent() throws {
        let chore = try assign(title: "Homework")
        let start = Date()
        try service.nudge(chore, by: parent, now: start)

        let first = try XCTUnwrap(notifier.events(household: household, me: kid).first { $0.title.hasPrefix("Reminder") })
        XCTAssertEqual(first.title, "Reminder from Mama")
        XCTAssertTrue(first.body.contains("Homework"))

        try service.nudge(chore, by: parent, now: start.addingTimeInterval(Self.minutes(11)))
        let second = try XCTUnwrap(notifier.events(household: household, me: kid).first { $0.title.hasPrefix("Reminder") })
        XCTAssertNotEqual(first.key, second.key, "a second reminder is news again")
    }

    func testKidsHearAboutBonusAndPayoutsButOnlyRecentOnes() throws {
        try service.setAllowance(rate: 10, currencyCode: "USD", for: household, by: parent)
        let bonus = try service.giveBonus(20, reason: "Helped your brother", to: kid, by: parent)
        XCTAssertEqual(titles(for: kid), ["Bonus! +20 points"])
        XCTAssertEqual(notifier.events(household: household, me: kid).first?.body, "Helped your brother")

        let payout = try service.payOut(10, to: kid, by: parent)
        XCTAssertEqual(titles(for: kid).count, 2)
        XCTAssertTrue(notifier.events(household: household, me: kid).contains { $0.body == "For 10 points." })

        bonus.date = Date().addingTimeInterval(-2 * 86_400)
        payout.date = Date().addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(titles(for: kid), [], "yesterday's news isn't repeated")
    }

    func testParentsDoNotGetKidNews() throws {
        _ = try assign()
        _ = try service.giveBonus(5, reason: "Nice", to: kid, by: parent)
        XCTAssertEqual(titles(for: parent), [])
    }

    // MARK: Telling people once

    func testTheFirstSyncStaysQuietThenOnlyNewThingsAreDelivered() throws {
        _ = try assign(title: "Dishes")

        let first = notifier.claimNewEvents(household: household, me: kid)
        XCTAssertEqual(first.fresh, [], "installing shouldn't flood the kid with old news")
        XCTAssertEqual(first.total, 1)

        XCTAssertEqual(notifier.claimNewEvents(household: household, me: kid).fresh, [], "nothing changed")

        _ = try assign(title: "Laundry")
        let later = notifier.claimNewEvents(household: household, me: kid)
        XCTAssertEqual(later.fresh.map(\.title), ["New chore: Laundry"])
        XCTAssertEqual(later.total, 2)
        XCTAssertEqual(notifier.claimNewEvents(household: household, me: kid).fresh, [], "and only once")
    }

    func testEachPersonKeepsTheirOwnMemoryOfWhatTheyHaveSeen() throws {
        let other = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        _ = notifier.claimNewEvents(household: household, me: kid)
        _ = notifier.claimNewEvents(household: household, me: other)

        _ = try assign(title: "Shared job", to: kid)
        XCTAssertEqual(notifier.claimNewEvents(household: household, me: kid).fresh.count, 1)
        XCTAssertEqual(notifier.claimNewEvents(household: household, me: other).fresh.count, 0)
    }

    func testAParentsBadgeCountsEverythingWaiting() throws {
        _ = notifier.claimNewEvents(household: household, me: parent)
        let chore = try assign()
        try service.markComplete(chore, by: kid, note: nil, photo: nil)

        let result = notifier.claimNewEvents(household: household, me: parent)
        XCTAssertEqual(result.fresh.map(\.title), ["Sam finished a chore"])
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.fresh.first?.category, .choreReview)
        XCTAssertEqual(result.fresh.first?.objectID, chore.id)
    }

    // MARK: The Sunday reminder

    func testTheWeeklyRecapIsARepeatingSundayEveningRequest() throws {
        let request = Notifier.weeklyRecapRequest
        XCTAssertEqual(request.identifier, Notifier.weeklyRecapID)
        XCTAssertEqual(request.content.title, "How did the week go?")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.weekday, 1)
        XCTAssertEqual(trigger.dateComponents.hour, 18)
    }

    private static func minutes(_ count: Double) -> TimeInterval { count * 60 }
}
