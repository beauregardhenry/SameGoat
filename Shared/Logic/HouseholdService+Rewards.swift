import CoreData

// Rewards, goals, and spending points on them.
extension HouseholdService {
    // MARK: Rewards

    @discardableResult
    func saveReward(_ reward: Reward?, title: String, emoji: String, cost: Int, isActive: Bool,
                    in household: Household, by me: Member) throws -> Reward {
        try requireParent(me)
        let title = title.trimmed
        guard !title.isEmpty else { throw ServiceError.invalid(String(localized: "Give the reward a name.")) }
        guard cost > 0 else { throw ServiceError.invalid(String(localized: "A reward needs to cost at least 1 point.")) }
        let target = try reward ?? insert(Reward.self, into: household)
        if reward == nil {
            target.id = UUID()
            target.createdAt = Date()
            target.household = household
        }
        target.title = title
        target.emoji = emoji.trimmed.nilIfEmpty ?? "🎁"
        target.cost = Int32(cost)
        target.isActive = isActive
        try save()
        return target
    }

    /// A kid picks a reward to save toward, or a parent picks it for them. nil clears it.
    func setGoal(_ reward: Reward?, for kid: Member, by me: Member) throws {
        guard !kid.isParent else { throw ServiceError.invalid(String(localized: "Only kids save toward rewards.")) }
        guard me.isParent || me.id == kid.id else { throw ServiceError.notAllowed(String(localized: "You can only pick your own goal.")) }
        if let reward, !reward.isActive || reward.household != kid.household {
            throw ServiceError.invalid(String(localized: "That reward isn't available."))
        }
        kid.goalRewardID = reward?.id
        try save()
    }

    func deleteReward(_ reward: Reward, by me: Member) throws {
        try requireParent(me)
        context.delete(reward)
        try save()
    }

    func requestRedemption(of reward: Reward, by me: Member) throws {
        guard !me.isParent else { throw ServiceError.notAllowed(String(localized: "Only kids spend points.")) }
        guard reward.isActive, let household = reward.household else { throw ServiceError.invalid(String(localized: "That reward isn't available.")) }
        guard me.available >= Int(reward.cost) else {
            throw ServiceError.invalid(String(localized: "You need \(Int(reward.cost) - me.available) more points for that."))
        }
        let request = try insert(Redemption.self, into: household)
        request.id = UUID()
        request.rewardTitle = reward.title
        request.rewardEmoji = reward.emoji
        request.cost = reward.cost
        request.status = .requested
        request.requestedAt = Date()
        request.member = me
        request.household = household
        try save()
    }

    /// Approving spends the points; denying leaves the balance untouched.
    func decide(_ redemption: Redemption, approve: Bool, by me: Member) throws {
        try requireParent(me)
        guard redemption.status == .requested else { throw ServiceError.invalid(String(localized: "This request was already decided.")) }
        guard let kid = redemption.member, let household = redemption.household else { throw ServiceError.invalid(String(localized: "This request has no owner.")) }

        if approve {
            guard kid.balance >= Int(redemption.cost) else {
                throw ServiceError.invalid(String(localized: "\(kid.displayName) doesn't have enough points anymore."))
            }
            let entry = try addEntry(-redemption.cost, kind: .redemption, reason: redemption.displayTitle, to: kid, in: household)
            entry.redemptionID = redemption.id
        }
        redemption.status = approve ? .approved : .denied
        redemption.decidedAt = Date()
        redemption.decidedByName = me.name
        try save()
    }
}
