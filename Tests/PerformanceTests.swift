import XCTest
@testable import HappyMama

/// A family with a year of history: the things that recount it on every screen must stay quick.
@MainActor
final class PerformanceTests: ServiceTestCase {
    private var kids: [Member] = []

    override func setUp() async throws {
        try await super.setUp()
        let pip = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        let ava = try service.addMember(name: "Ava", role: .kid, emoji: "🦊", to: household, by: parent)
        kids = [kid, pip, ava]
        seedYear()
    }

    /// 365 days × 3 kids × 4 approved chores (with their points), a few open ones, and daily check-ins.
    private func seedYear() {
        let context = service.context
        let today = calendar.startOfDay(for: Date())
        let titles = ["Dishes", "Make your bed", "Feed the pet", "Tidy your room"]
        for back in 0..<365 {
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            for kid in kids {
                for title in titles {
                    let chore = Chore(context: context)
                    chore.id = UUID()
                    chore.title = title
                    chore.points = 5
                    chore.awardedPoints = 5
                    chore.minutes = 10
                    chore.status = .approved
                    chore.createdAt = day
                    chore.completedAt = day.addingTimeInterval(3600 * 17)
                    chore.reviewedAt = chore.completedAt
                    chore.assignee = kid
                    chore.household = household
                    let entry = PointEntry(context: context)
                    entry.id = UUID()
                    entry.amount = 5
                    entry.kind = .chore
                    entry.reason = title
                    entry.date = chore.reviewedAt
                    entry.choreID = chore.id
                    entry.member = kid
                    entry.household = household
                }
            }
            for member in household.memberList {
                let mood = MoodCheckIn(context: context)
                mood.id = UUID()
                mood.day = day
                mood.rating = Int16(2 + (back + Int(member.colorIndex)) % 4)
                mood.createdAt = day.addingTimeInterval(3600 * 20)
                mood.member = member
                mood.household = household
            }
        }
        for kid in kids {
            for title in titles {
                let open = Chore(context: context)
                open.id = UUID()
                open.title = title
                open.status = .todo
                open.minutes = 10
                open.dueDate = today
                open.createdAt = today
                open.assignee = kid
                open.household = household
            }
        }
        try? context.save()
    }

    /// Runs `work` and fails if it takes longer than `limit` seconds.
    private func timed(_ name: String, under limit: TimeInterval, _ work: () -> Void) {
        let start = Date()
        work()
        let seconds = Date().timeIntervalSince(start)
        print("⏱ \(name): \(String(format: "%.3f", seconds))s")
        XCTAssertLessThan(seconds, limit, "\(name) took \(seconds)s")
    }

    func testAYearOfHistoryStaysQuick() throws {
        XCTAssertEqual((household.chores as? Set<Chore>)?.count, 365 * 3 * 4 + 12)
        timed("balance", under: 0.2) { _ = kid.balance; _ = kid.available }
        timed("streak", under: 0.2) { _ = kid.streak(calendar: calendar) }
        timed("badges", under: 0.3) { _ = Badges.all(for: kid, calendar: calendar) }
        let open = try XCTUnwrap(kid.assignedChores?.compactMap { $0 as? Chore }.first { $0.status == .todo })
        timed("level", under: 0.2) { _ = ChoreLevel.of(open) }
        timed("mood trend", under: 0.15) { _ = FamilyMood.trend(days: 14, in: household, calendar: calendar) }
        timed("mood insights", under: 0.3) { _ = MoodInsights.insights(for: household, calendar: calendar) }
        timed("boosters", under: 0.2) { _ = MoodInsights.suggestedBoosters(for: household, calendar: calendar) }
        timed("workload", under: 0.3) { _ = MoodInsights.workloadNotes(for: household, calendar: calendar) }
        timed("weekly recap", under: 0.4) { _ = WeeklyRecap.summaries(for: kids, calendar: calendar) }
        timed("widget", under: 0.5) { _ = WidgetSnapshot(household: household, me: parent, calendar: calendar) }
        timed("energy plan", under: 0.2) { _ = Spoons.plan(for: kid, spoons: 2, calendar: calendar) }
        timed("celebrations", under: 0.3) { _ = Celebrations.candidates(for: kid, now: Date(), calendar: calendar) }
        timed("sync cleanup", under: 0.3) { try? service.resolveSyncDuplicates(in: household) }
    }
}
