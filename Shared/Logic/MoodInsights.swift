import Foundation

/// Gentle, local observations from check-ins, plus ideas to lift the family's mood.
/// They describe what tends to happen together, never what causes what, and they wait
/// for enough data so a couple of odd days don't turn into a "pattern".
enum MoodInsights {
    struct Insight: Identifiable, Equatable {
        let id: String
        let text: String
        /// How big the difference is, for putting the clearest ones first.
        let strength: Double
    }

    static let weeksLookedAt = 8
    static let habitTimesPerWeek = 3
    static let minimumDifference = 0.5
    static let minimumWeeks = 2
    static let minimumDays = 4

    // MARK: Insights

    static func insights(for household: Household, now: Date = Date(), calendar: Calendar = .current) -> [Insight] {
        let weekly = weeklyHabits(household, now: now, calendar: calendar)
        // One observation per habit: the weekly one says it better than the daily one.
        let covered = Set(weekly.map { $0.id.replacingOccurrences(of: "week-", with: "") })
        let daily = oneOffDays(household, now: now, calendar: calendar)
            .filter { !covered.contains($0.id.replacingOccurrences(of: "day-", with: "")) }
        return (weekly + daily)
            .sorted { $0.strength > $1.strength }
            .prefix(3)
            .map { $0 }
    }

    /// Finished chores in the window, grouped by who did them and what they were called.
    private static func finished(_ household: Household, since: Date) -> [String: [Chore]] {
        Dictionary(grouping: ((household.chores as? Set<Chore>) ?? []).filter {
            $0.status == .approved && ($0.completedAt ?? .distantPast) >= since && $0.assignee != nil
        }) { "\($0.assignee?.id?.uuidString ?? "")|\($0.displayTitle.lowercased())" }
    }

    /// "On weeks you went to the gym 3+ times, the family's mood averaged 4.2, compared with 3.4."
    private static func weeklyHabits(_ household: Household, now: Date, calendar: Calendar) -> [Insight] {
        let thisWeek = WeeklyRecap.weekStart(for: now, calendar: calendar)
        let weeks = (0..<weeksLookedAt).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        guard let first = weeks.last else { return [] }
        let daily = FamilyMood.dailyAverages(in: household, calendar: calendar)
        let moodByWeek = Dictionary(uniqueKeysWithValues: weeks.compactMap { start -> (Date, Double)? in
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            let averages = days.compactMap { daily[$0] }
            return averages.count >= 3 ? (start, averages.reduce(0, +) / Double(averages.count)) : nil
        })
        var result: [Insight] = []
        for (key, chores) in finished(household, since: first) {
            guard let sample = chores.first, let who = sample.assignee else { continue }
            let counts = Dictionary(grouping: chores) { WeeklyRecap.weekStart(for: $0.completedAt ?? now, calendar: calendar) }
                .mapValues(\.count)
            let often = moodByWeek.filter { (counts[$0.key] ?? 0) >= habitTimesPerWeek }.map(\.value)
            let rarely = moodByWeek.filter { (counts[$0.key] ?? 0) < habitTimesPerWeek }.map(\.value)
            guard often.count >= minimumWeeks, rarely.count >= minimumWeeks else { continue }
            let high = often.reduce(0, +) / Double(often.count), low = rarely.reduce(0, +) / Double(rarely.count)
            guard high - low >= minimumDifference else { continue }
            result.append(Insight(
                id: "week-\(key)",
                text: String(localized: "On weeks \(who.displayName) did “\(sample.displayTitle)” \(habitTimesPerWeek)+ times, the family's mood averaged \(high.formatted(.number.precision(.fractionLength(1)))), compared with \(low.formatted(.number.precision(.fractionLength(1)))) other weeks."),
                strength: high - low))
        }
        return result
    }

    /// "Days with family game night averaged 4.5, other days 3.6." For things done on some days, not most.
    private static func oneOffDays(_ household: Household, now: Date, calendar: Calendar) -> [Insight] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(weeksLookedAt * 7 - 1), to: today) else { return [] }
        let days = (0..<(weeksLookedAt * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let daily = FamilyMood.dailyAverages(in: household, calendar: calendar)
        let moodByDay = Dictionary(uniqueKeysWithValues: days.compactMap { day in daily[day].map { (day, $0) } })
        var result: [Insight] = []
        for (key, chores) in finished(household, since: first) {
            guard let sample = chores.first else { continue }
            let doneDays = Set(chores.compactMap { $0.completedAt.map { calendar.startOfDay(for: $0) } })
            let with = moodByDay.filter { doneDays.contains($0.key) }.map(\.value)
            let without = moodByDay.filter { !doneDays.contains($0.key) }.map(\.value)
            // Daily habits belong to the weekly view; this is for occasional things.
            guard with.count >= minimumDays, without.count >= with.count else { continue }
            let high = with.reduce(0, +) / Double(with.count), low = without.reduce(0, +) / Double(without.count)
            guard high - low >= minimumDifference + 0.1 else { continue }
            result.append(Insight(
                id: "day-\(key)",
                text: String(localized: "Days with “\(sample.displayTitle)” averaged \(high.formatted(.number.precision(.fractionLength(1)))) for family mood, other days \(low.formatted(.number.precision(.fractionLength(1))))."),
                strength: high - low - 0.05))
        }
        return result
    }

    // MARK: Boosters

    struct Booster: Identifiable, Equatable {
        let emoji: String
        let title: String
        /// Fine for a tired, low day.
        let lowEnergy: Bool
        var id: String { title }
    }

    static let boosters: [Booster] = [
        Booster(emoji: "🚶", title: String(localized: "Family walk"), lowEnergy: true),
        Booster(emoji: "🎬", title: String(localized: "Movie night with popcorn"), lowEnergy: true),
        Booster(emoji: "📚", title: String(localized: "Read together"), lowEnergy: true),
        Booster(emoji: "📞", title: String(localized: "Call the grandparents"), lowEnergy: true),
        Booster(emoji: "🧩", title: String(localized: "Puzzle time"), lowEnergy: true),
        Booster(emoji: "🎲", title: String(localized: "Family game night"), lowEnergy: false),
        Booster(emoji: "🍪", title: String(localized: "Bake something together"), lowEnergy: false),
        Booster(emoji: "💃", title: String(localized: "Kitchen dance party"), lowEnergy: false),
        Booster(emoji: "🧺", title: String(localized: "Picnic"), lowEnergy: false),
        Booster(emoji: "🌳", title: String(localized: "Trip to the park"), lowEnergy: false),
        Booster(emoji: "🍳", title: String(localized: "Make breakfast together"), lowEnergy: false),
        Booster(emoji: "🎨", title: String(localized: "Art afternoon"), lowEnergy: true),
    ]

    /// Ideas for lifting the mood: ones that went well before come first, then gentle ones
    /// when the week has been rough, then the rest.
    static func suggestedBoosters(for household: Household, now: Date = Date(), calendar: Calendar = .current) -> [(booster: Booster, before: Double?)] {
        let recent = FamilyMood.trend(days: 7, in: household, now: now, calendar: calendar).map(\.average)
        let rough = !recent.isEmpty && recent.reduce(0, +) / Double(recent.count) < 3
        let daily = FamilyMood.dailyAverages(in: household, calendar: calendar)
        let titles = Set(boosters.map(\.title))
        let done = ((household.chores as? Set<Chore>) ?? []).filter { $0.status == .approved && titles.contains($0.displayTitle) }
        let scored = boosters.map { booster -> (Booster, Double?) in
            let days = done.filter { $0.displayTitle == booster.title }
                .compactMap { $0.completedAt.map { calendar.startOfDay(for: $0) } }
            let moods = days.compactMap { daily[$0] }
            return (booster, moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count))
        }
        return scored.sorted { a, b in
            if (a.1 ?? 0) != (b.1 ?? 0) { return (a.1 ?? 0) > (b.1 ?? 0) }
            if rough && a.0.lowEnergy != b.0.lowEnergy { return a.0.lowEnergy }
            return false
        }
        .prefix(4)
        .map { ($0.0, $0.1) }
    }

    // MARK: Workload

    /// For parents: a kid whose mood has been low this week and who has more to do than the others.
    static func workloadNotes(for household: Household, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let kids = household.kids
        guard kids.count > 1 else { return [] }
        let loads = Dictionary(uniqueKeysWithValues: kids.map { ($0.objectID, Effort.openMinutes(for: $0, now: now, calendar: calendar)) })
        let average = Double(loads.values.reduce(0, +)) / Double(kids.count)
        return kids.compactMap { kid in
            guard let mood = FamilyMood.average(for: kid, days: 7, now: now, calendar: calendar), mood <= 2.5,
                  let load = loads[kid.objectID], Double(load) > average, load > 0 else { return nil }
            return String(localized: "\(kid.displayName)'s mood has been low this week, and they have the most to do (\(load) min). Maybe lighten the load or plan something fun together.")
        }
    }
}

extension HouseholdService {
    /// Puts a mood booster on today's list as a grown-up's chore, so the kids can see it's coming.
    @discardableResult
    func planBooster(_ booster: MoodInsights.Booster, by me: Member, now: Date = Date()) throws -> Chore {
        guard me.isParent, let household = me.household else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
        var draft = ChoreDraft()
        draft.title = booster.title
        draft.emoji = booster.emoji
        draft.points = 0
        draft.dueDate = now
        draft.whyItHelps = String(localized: "Time together lifts everyone's mood.")
        return try createChores(draft, assignees: [me], in: household, by: me)[0]
    }
}
