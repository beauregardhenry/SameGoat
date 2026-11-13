import CoreData

// Bonus points and turning points into allowance money.
extension HouseholdService {
    // MARK: Bonus points

    static let bonusRange = 1...1000

    /// A parent gives points for something that wasn't a chore ("Helped your brother").
    @discardableResult
    func giveBonus(_ points: Int, reason: String, to kid: Member, by me: Member) throws -> PointEntry {
        try requireParent(me)
        guard !kid.isParent, let household = kid.household else { throw ServiceError.invalid(String(localized: "Bonus points are for kids.")) }
        guard Self.bonusRange.contains(points) else { throw ServiceError.invalid(String(localized: "Give between 1 and 1,000 points.")) }
        let entry = try addEntry(Int32(points), kind: .bonus, reason: reason.trimmed.nilIfEmpty ?? String(localized: "Bonus"), to: kid, in: household)
        try save()
        return entry
    }

    // MARK: Allowance

    static let allowanceRates = 1...1000

    /// Turns allowance mode on (`rate` points per unit of `currencyCode`) or off (nil).
    func setAllowance(rate: Int?, currencyCode: String, for household: Household, by me: Member) throws {
        try requireParent(me)
        if let rate {
            guard Self.allowanceRates.contains(rate) else { throw ServiceError.invalid(String(localized: "Use between 1 and 1,000 points per unit.")) }
            household.allowanceRate = Int16(rate)
            household.currencyCode = currencyCode
        } else {
            household.allowanceRate = 0
        }
        try save()
    }

    /// A parent pays a kid real money for some of their points, which spends those points.
    @discardableResult
    func payOut(_ points: Int, to kid: Member, by me: Member) throws -> PointEntry {
        try requireParent(me)
        guard !kid.isParent, let household = kid.household else { throw ServiceError.invalid(String(localized: "Only kids get paid out.")) }
        guard let money = household.moneyText(for: points) else { throw ServiceError.invalid(String(localized: "Turn on allowance mode first.")) }
        guard points > 0 else { throw ServiceError.invalid(String(localized: "Pay out at least 1 point.")) }
        guard points <= kid.available else { throw ServiceError.invalid(String(localized: "\(kid.displayName) has \(kid.available) points to pay out.")) }
        let entry = try addEntry(Int32(-points), kind: .payout, reason: String(localized: "Paid \(money)"), to: kid, in: household)
        try save()
        return entry
    }
}
