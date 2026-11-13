import CoreData

// Family-wide settings parents control: the vacation pause and the effort rate.
extension HouseholdService {
    // MARK: Vacation pause

    /// Pauses chores from `from` through `until` (whole days), or clears the pause with nil.
    func setPause(from: Date?, until: Date?, for household: Household, by me: Member) throws {
        try requireParent(me)
        if let from, let until {
            let start = calendar.startOfDay(for: from), end = calendar.startOfDay(for: until)
            guard end >= start else { throw ServiceError.invalid(String(localized: "The pause has to end after it starts.")) }
            guard end >= calendar.startOfDay(for: Date()) else { throw ServiceError.invalid(String(localized: "Pick dates that haven't passed yet.")) }
            household.pausedFrom = start
            household.pausedUntil = end
        } else {
            household.pausedFrom = nil
            household.pausedUntil = nil
        }
        try save()
    }

    // MARK: Effort

    /// How many points every 5 minutes of a chore suggests, before difficulty.
    func setEffortRate(_ rate: Int, for household: Household, by me: Member) throws {
        try requireParent(me)
        guard Effort.rateRange.contains(rate) else { throw ServiceError.invalid(String(localized: "Use between 1 and 20 points.")) }
        household.effortRate = Int16(rate)
        try save()
    }
}
