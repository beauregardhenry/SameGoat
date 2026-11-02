import Foundation

/// How each kid did this week, and the weeks before, for the recap screen.
enum WeeklyRecap {
    struct Week: Equatable {
        let start: Date
        let points: Int
    }

    struct KidWeek: Identifiable, Equatable {
        let id: UUID
        let name: String
        let emoji: String
        /// Points earned this week (chores and bonuses; spending doesn't count against it).
        let points: Int
        let choresDone: Int
        let streak: Int
        /// Oldest first, ending with this week.
        let history: [Week]
    }

    static let weeksShown = 8

    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func summaries(for kids: [Member], now: Date = Date(), calendar: Calendar = .current) -> [KidWeek] {
        let thisWeek = weekStart(for: now, calendar: calendar)
        let starts = (0..<weeksShown).reversed().compactMap {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)
        }
        return kids.compactMap { kid in
            guard let id = kid.id else { return nil }
            let earned = kid.entryList.filter { $0.amount > 0 }
            let history = starts.map { start in
                Week(start: start, points: earned
                    .filter { ($0.date.map { weekStart(for: $0, calendar: calendar) }) == start }
                    .reduce(0) { $0 + Int($1.amount) })
            }
            let done = ((kid.assignedChores as? Set<Chore>) ?? []).filter {
                $0.status == .approved && $0.completedAt.map { weekStart(for: $0, calendar: calendar) } == thisWeek
            }.count
            return KidWeek(id: id, name: kid.displayName, emoji: kid.displayEmoji,
                           points: history.last?.points ?? 0, choresDone: done,
                           streak: kid.streak(now: now, calendar: calendar), history: history)
        }
    }

    /// One line to sum up the week.
    static func headline(_ weeks: [KidWeek]) -> String {
        guard !weeks.isEmpty else { return "Add a kid to see their week." }
        let total = weeks.reduce(0) { $0 + $1.points }
        guard total > 0 else { return "A quiet week so far. There's still time!" }
        let chores = weeks.reduce(0) { $0 + $1.choresDone }
        let summary = "\(count(total, "point")) and \(count(chores, "chore")) this week."
        return weeks.count == 1 ? summary.prefix(1).uppercased() + summary.dropFirst() : "Together: " + summary
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// Sunday at 6pm, when parents get a nudge to look at the week.
    static let reminderTime: DateComponents = {
        var parts = DateComponents()
        parts.weekday = 1
        parts.hour = 18
        return parts
    }()
}
