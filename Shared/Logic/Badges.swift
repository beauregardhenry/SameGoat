import Foundation

/// Milestones a kid earns from what they've already done. Worked out from the data each
/// time, so they sync for free and can't get out of step with the history.
struct Badge: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    let earned: Bool
}

enum Badges {
    static func all(for kid: Member, now: Date = Date(), calendar: Calendar = .current) -> [Badge] {
        let chores = ((kid.assignedChores as? Set<Chore>) ?? []).filter { $0.status == .approved }.count
        let earned = kid.entryList.filter { $0.amount > 0 }.reduce(0) { $0 + Int($1.amount) }
        let redeemed = ((kid.redemptions as? Set<Redemption>) ?? []).contains { $0.status == .approved }
        let best = bestStreak(for: kid, calendar: calendar)
        return [
            Badge(id: "chores-1", emoji: "🌱", title: "First chore", detail: "Finish your first chore.", earned: chores >= 1),
            Badge(id: "chores-10", emoji: "🧹", title: "Helper", detail: "Finish 10 chores.", earned: chores >= 10),
            Badge(id: "chores-50", emoji: "🦸", title: "Superhelper", detail: "Finish 50 chores.", earned: chores >= 50),
            Badge(id: "streak-3", emoji: "🔥", title: "On a roll", detail: "Do chores 3 days in a row.", earned: best >= 3),
            Badge(id: "streak-7", emoji: "⚡️", title: "Week streak", detail: "Do chores 7 days in a row.", earned: best >= 7),
            Badge(id: "streak-30", emoji: "🏆", title: "Month streak", detail: "Do chores 30 days in a row.", earned: best >= 30),
            Badge(id: "points-100", emoji: "💯", title: "100 points", detail: "Earn 100 points in all.", earned: earned >= 100),
            Badge(id: "redeemed-1", emoji: "🎁", title: "Treat yourself", detail: "Get your first reward.", earned: redeemed),
        ]
    }

    /// The longest run of consecutive days with a chore turned in, ever.
    static func bestStreak(for kid: Member, calendar: Calendar = .current) -> Int {
        let days = Set(((kid.assignedChores as? Set<Chore>) ?? []).compactMap { chore -> Date? in
            guard chore.status != .todo, let done = chore.completedAt else { return nil }
            return calendar.startOfDay(for: done)
        }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}
