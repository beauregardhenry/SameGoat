import Foundation

/// Matches chores to how much energy someone has right now, in "spoons" (1 to 3).
/// Chores due today always come first, whatever the energy, because deadlines still matter.
enum Spoons {
    static let range = 1...3

    struct Plan: Equatable {
        /// Due today or late: these can't wait.
        var mustDo: [Chore] = []
        /// Not urgent, and they fit the energy you have.
        var fits: [Chore] = []
        /// Not urgent, and they'd take more than you have right now.
        var later: [Chore] = []
    }

    static func plan(for me: Member, spoons: Int, now: Date = Date(), calendar: Calendar = .current) -> Plan {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let open = ((me.assignedChores as? Set<Chore>) ?? [])
            .filter { $0.status == .todo && !$0.isOnHold(now: now, calendar: calendar) }
            .sorted { ($0.dueAt(calendar: calendar) ?? .distantFuture, $0.spoons, $0.displayTitle)
                < ($1.dueAt(calendar: calendar) ?? .distantFuture, $1.spoons, $1.displayTitle) }
        var plan = Plan()
        for chore in open {
            if !chore.extraCredit, let due = chore.dueDate, due < tomorrow {
                plan.mustDo.append(chore)
            } else if chore.spoons <= spoons {
                plan.fits.append(chore)
            } else {
                plan.later.append(chore)
            }
        }
        return plan
    }
}
