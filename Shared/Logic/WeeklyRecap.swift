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
        /// Roughly how long this week's finished chores took, from their time estimates.
        let minutes: Int
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
        guard let first = starts.first else { return [] }
        return kids.compactMap { kid in
            guard let id = kid.id else { return nil }
            // Bucket each recent point by its week once, rather than once per week shown.
            var pointsByWeek: [Date: Int] = [:]
            for entry in kid.entryList where entry.amount > 0 {
                guard let date = entry.date, date >= first else { continue }
                pointsByWeek[weekStart(for: date, calendar: calendar), default: 0] += Int(entry.amount)
            }
            let history = starts.map { Week(start: $0, points: pointsByWeek[$0] ?? 0) }
            let done = ((kid.assignedChores as? Set<Chore>) ?? []).filter {
                guard $0.status == .approved, let completed = $0.completedAt, completed >= thisWeek else { return false }
                return weekStart(for: completed, calendar: calendar) == thisWeek
            }
            return KidWeek(id: id, name: kid.displayName, emoji: kid.displayEmoji,
                           points: history.last?.points ?? 0, choresDone: done.count,
                           minutes: done.reduce(0) { $0 + ($1.minutes ?? 0) },
                           streak: kid.streak(now: now, calendar: calendar), history: history)
        }
    }

    /// One line to sum up the week.
    static func headline(_ weeks: [KidWeek]) -> String {
        guard !weeks.isEmpty else { return String(localized: "Add a kid to see their week.") }
        let total = weeks.reduce(0) { $0 + $1.points }
        guard total > 0 else { return String(localized: "A quiet week so far. There's still time!") }
        let chores = weeks.reduce(0) { $0 + $1.choresDone }
        let pointsText = String(localized: "\(total) points")
        let choresText = String(localized: "\(chores) chores")
        return weeks.count == 1
            ? String(localized: "\(pointsText) and \(choresText) this week.")
            : String(localized: "Together: \(pointsText) and \(choresText) this week.")
    }

    /// Sunday at 6pm, when parents get a nudge to look at the week.
    static let reminderTime: DateComponents = {
        var parts = DateComponents()
        parts.weekday = 1
        parts.hour = 18
        return parts
    }()
}
