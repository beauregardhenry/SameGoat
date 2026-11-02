import Foundation

/// Something worth confetti, shown to a kid the next time they open the app.
struct Celebration: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let message: String
}

/// Works out what a kid hasn't celebrated yet on this device, and remembers what they have.
@MainActor
final class Celebrations: ObservableObject {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// New points from the last week, newly earned badges, and a goal they can now afford.
    /// The first time a kid opens the app on a device, everything so far counts as seen.
    func pending(for kid: Member, now: Date = Date(), calendar: Calendar = .current) -> [Celebration] {
        guard !kid.isParent, let key = storageKey(kid) else { return [] }
        let current = Self.candidates(for: kid, now: now, calendar: calendar)
        guard let seen = defaults.stringArray(forKey: key).map(Set.init) else {
            defaults.set(current.map(\.id), forKey: key)
            return []
        }
        return current.filter { !seen.contains($0.id) }
    }

    func markSeen(_ celebration: Celebration, for kid: Member) {
        guard let key = storageKey(kid) else { return }
        var seen = defaults.stringArray(forKey: key) ?? []
        if !seen.contains(celebration.id) { seen.append(celebration.id) }
        defaults.set(seen, forKey: key)
    }

    static func candidates(for kid: Member, now: Date, calendar: Calendar) -> [Celebration] {
        var result: [Celebration] = []
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        for entry in kid.entryList.reversed() where entry.amount > 0 && (entry.date ?? .distantPast) > weekAgo {
            let reason = entry.reason ?? String(localized: "your chore")
            result.append(Celebration(
                id: "entry-\(entry.id?.uuidString ?? "")",
                emoji: entry.kind == .bonus ? "🌟" : "🎉",
                title: String(localized: "+\(entry.amount) points!"),
                message: entry.kind == .bonus ? String(localized: "Bonus: \(reason)") : String(localized: "\(reason) was approved.")))
        }
        for badge in Badges.all(for: kid, now: now, calendar: calendar) where badge.earned {
            result.append(Celebration(id: "badge-\(badge.id)", emoji: badge.emoji,
                                      title: String(localized: "New badge: \(badge.title)"), message: badge.detail))
        }
        if let goal = kid.goal, kid.available >= Int(goal.cost), let id = goal.id {
            result.append(Celebration(id: "goal-\(id.uuidString)", emoji: goal.displayEmoji,
                                      title: String(localized: "You can get \(goal.displayTitle)!"),
                                      message: String(localized: "You saved \(goal.cost) points. Ask for it in Rewards.")))
        }
        return result
    }

    private func storageKey(_ kid: Member) -> String? {
        kid.id.map { "celebrated.\($0.uuidString)" }
    }
}
