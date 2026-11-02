import Foundation

/// What Siri and Shortcuts say and do. Kept apart from the App Intents types so the
/// wording and the rules can be tested without the system running an intent.
@MainActor
enum AssistantReplies {
    /// The chores this person could say they've finished: their own open ones, soonest due first.
    static func openChores(for me: Member) -> [Chore] {
        guard !me.isParent else { return [] }
        return ((me.assignedChores as? Set<Chore>) ?? [])
            .filter { $0.status == .todo }
            .sorted { ($0.dueAt() ?? .distantFuture, $0.displayTitle) < ($1.dueAt() ?? .distantFuture, $1.displayTitle) }
    }

    /// Open chores whose title contains the spoken words, ignoring case and accents.
    static func openChores(for me: Member, matching words: String) -> [Chore] {
        let words = words.trimmed
        guard !words.isEmpty else { return openChores(for: me) }
        return openChores(for: me).filter {
            $0.displayTitle.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Marks the chore done and says what happens next.
    static func finish(_ choreID: UUID, household: Household, me: Member, service: HouseholdService) throws -> String {
        guard let chore = ((household.chores as? Set<Chore>) ?? []).first(where: { $0.id == choreID }) else {
            throw ServiceError.invalid(String(localized: "I couldn't find that chore."))
        }
        try service.markComplete(chore, by: me, note: nil, photo: nil)
        if chore.status == .approved {
            return String(localized: "Nice work! You earned \(Int(chore.awardedPoints)) points for \(chore.displayTitle).")
        }
        return String(localized: "Nice work! \(chore.displayTitle) is waiting for a parent to check.")
    }

    /// For a parent: what's waiting for them. For a kid: what they still have to do today.
    /// Whole sentences per case, with plurals from the String Catalog, so they translate.
    static func summary(household: Household, me: Member, now: Date = Date(), calendar: Calendar = .current) -> String {
        if me.isParent {
            let chores = ((household.chores as? Set<Chore>) ?? []).filter { $0.status == .pendingReview }.count
            let requests = ((household.redemptions as? Set<Redemption>) ?? []).filter { $0.status == .requested }.count
            switch (chores, requests) {
            case (0, 0): return String(localized: "You're all caught up. Nothing is waiting for review.")
            case (_, 0): return String(localized: "\(chores) chores are waiting for you.")
            case (0, _): return String(localized: "\(requests) reward requests are waiting for you.")
            default:
                let choresText = String(localized: "\(chores) chores")
                let requestsText = String(localized: "\(requests) reward requests")
                return String(localized: "\(choresText) and \(requestsText) are waiting for you.")
            }
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return "" }
        let today = openChores(for: me).filter { ($0.dueDate ?? .distantPast) < tomorrow }
        let names = today.prefix(3).map(\.displayTitle).formatted(.list(type: .and))
        switch today.count {
        case 0: return String(localized: "You're all done for today!")
        case 1...3: return String(localized: "\(today.count) chores left today: \(names).")
        default: return String(localized: "\(today.count) chores left today, starting with \(names).")
        }
    }

    /// A kid's points and goal, or every kid's points for a parent.
    static func points(household: Household, me: Member) -> String {
        if me.isParent {
            let kids = household.kids
            guard !kids.isEmpty else { return String(localized: "There are no kids in your household yet.") }
            return kids.map { String(localized: "\($0.displayName): \($0.available) points") }.formatted(.list(type: .and)) + "."
        }
        var parts = [String(localized: "You have \(me.available) points.")]
        if let money = household.moneyText(for: me.available) { parts.append(String(localized: "That's \(money).")) }
        if me.reserved > 0 { parts.append(String(localized: "\(me.reserved) points are on hold for a reward request.")) }
        if let goal = me.goal {
            let left = Int(goal.cost) - me.available
            parts.append(left > 0
                ? String(localized: "\(left) more points for \(goal.displayTitle).")
                : String(localized: "That's enough for \(goal.displayTitle)!"))
        }
        return parts.joined(separator: " ")
    }
}
