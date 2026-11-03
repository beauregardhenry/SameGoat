import XCTest
@testable import SameGoat

@MainActor
final class BadgeTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }

    /// A chore turned in `daysAgo` and approved.
    private func done(daysAgo: Int, points: Int = 10) throws {
        let chore = try assign(points: points)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        chore.completedAt = calendar.date(byAdding: .day, value: -daysAgo, to: today)?.addingTimeInterval(3600)
        try service.approve(chore, by: parent)
    }

    private func earned() -> Set<String> {
        Set(Badges.all(for: kid, calendar: calendar).filter(\.earned).map(\.id))
    }

    func testNothingEarnedAtFirst() {
        XCTAssertTrue(earned().isEmpty)
        XCTAssertEqual(Badges.all(for: kid).count, 8)
    }

    func testChoreAndPointBadges() throws {
        try done(daysAgo: 0)
        XCTAssertEqual(earned(), ["chores-1"])
        for _ in 0..<9 { try done(daysAgo: 0) }
        XCTAssertEqual(earned(), ["chores-1", "chores-10", "points-100"])
    }

    func testStreakBadgesUseTheBestStreakEver() throws {
        for daysAgo in [20, 19, 18, 17, 16, 15, 14] { try done(daysAgo: daysAgo) }
        XCTAssertEqual(Badges.bestStreak(for: kid, calendar: calendar), 7)
        XCTAssertEqual(kid.streak(calendar: calendar), 0, "the current streak is long gone")
        XCTAssertTrue(earned().isSuperset(of: ["streak-3", "streak-7"]))
        XCTAssertFalse(earned().contains("streak-30"))
    }

    func testGapsResetTheRun() throws {
        for daysAgo in [10, 9, 7, 6, 5] { try done(daysAgo: daysAgo) }
        XCTAssertEqual(Badges.bestStreak(for: kid, calendar: calendar), 3)
    }

    func testFirstRewardBadge() throws {
        try done(daysAgo: 0, points: 10)
        let treat = try service.saveReward(nil, title: "Treat", emoji: "🍬", cost: 5, isActive: true, in: household, by: parent)
        try service.requestRedemption(of: treat, by: kid)
        XCTAssertFalse(earned().contains("redeemed-1"), "asking isn't getting")
        let request = try XCTUnwrap((household.redemptions as? Set<Redemption>)?.first)
        try service.decide(request, approve: true, by: parent)
        XCTAssertTrue(earned().contains("redeemed-1"))
    }

    func testBonusPointsCountTowardHundredButNotChores() throws {
        try service.giveBonus(100, reason: "Wow", to: kid, by: parent)
        XCTAssertEqual(earned(), ["points-100"])
    }
}

@MainActor
final class CelebrationTests: ServiceTestCase {
    private var defaults: UserDefaults!
    private var celebrations: Celebrations!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "CelebrationTests")
        defaults.removePersistentDomain(forName: "CelebrationTests")
        celebrations = Celebrations(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "CelebrationTests")
        try await super.tearDown()
    }

    private func approve(points: Int = 10, title: String = "Dishes") throws {
        let chore = try assign(title: title, points: points)
        try service.markComplete(chore, by: kid, note: nil, photo: nil)
        try service.approve(chore, by: parent)
    }

    func testFirstLookOnADeviceCelebratesNothingOld() throws {
        try approve()
        XCTAssertTrue(celebrations.pending(for: kid).isEmpty)
        try approve(title: "Bed")
        XCTAssertEqual(celebrations.pending(for: kid).map(\.title), ["+10 points!"])
    }

    func testNewPointsAndBadgesAreCelebratedOnce() throws {
        _ = celebrations.pending(for: kid)
        try approve()
        let pending = celebrations.pending(for: kid)
        XCTAssertEqual(pending.map(\.title), ["+10 points!", "New badge: First chore"])
        XCTAssertEqual(pending.first?.message, "Dishes was approved.")

        pending.forEach { celebrations.markSeen($0, for: kid) }
        XCTAssertTrue(celebrations.pending(for: kid).isEmpty)
        // Marking twice doesn't duplicate anything.
        pending.forEach { celebrations.markSeen($0, for: kid) }
        XCTAssertEqual(defaults.stringArray(forKey: "celebrated.\(try XCTUnwrap(kid.id).uuidString)")?.count, 2)
    }

    func testBonusAndReachedGoalAreCelebrated() throws {
        _ = celebrations.pending(for: kid)
        let movie = try service.saveReward(nil, title: "Movie", emoji: "🎬", cost: 5, isActive: true, in: household, by: parent)
        try service.setGoal(movie, for: kid, by: kid)
        try service.giveBonus(5, reason: "Kind", to: kid, by: parent)

        let titles = celebrations.pending(for: kid).map(\.title)
        XCTAssertEqual(titles, ["+5 points!", "You can get Movie!"])
        XCTAssertEqual(celebrations.pending(for: kid).first?.message, "Bonus: Kind")
        XCTAssertEqual(celebrations.pending(for: kid).first?.emoji, "🌟")
    }

    func testOldPointsAndParentsAreLeftOut() throws {
        _ = celebrations.pending(for: kid)
        let entry = try service.giveBonus(5, reason: "Kind", to: kid, by: parent)
        entry.date = Date().addingTimeInterval(-8 * 86_400)
        XCTAssertTrue(celebrations.pending(for: kid).isEmpty)
        XCTAssertTrue(celebrations.pending(for: parent).isEmpty)
    }
}
