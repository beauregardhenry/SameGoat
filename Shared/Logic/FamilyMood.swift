import CoreData

/// Daily family mood check-ins, and what they add up to. Everything is worked out on the
/// family's own devices from their own data; nothing is sent anywhere else.
enum FamilyMood {
    static let range = 1...5
    static let faces = ["😞", "🙁", "😐", "🙂", "😄"]

    static func face(_ rating: Int) -> String { faces[min(max(rating, 1), 5) - 1] }

    /// One check-in per person per day. If two devices both saved one before syncing,
    /// the later one counts (ties go to the lower id, the same on every device).
    static func checkIns(in household: Household) -> [MoodCheckIn] {
        let all = (household.moods as? Set<MoodCheckIn>) ?? []
        let grouped = Dictionary(grouping: all) { "\($0.member?.id?.uuidString ?? "")-\($0.day?.timeIntervalSince1970 ?? 0)" }
        return grouped.values.compactMap { group in
            group.max { a, b in
                (a.createdAt ?? .distantPast) != (b.createdAt ?? .distantPast)
                    ? (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
                    : syncOrder(b, a)
            }
        }
    }

    static func checkIn(by member: Member, on day: Date, calendar: Calendar = .current) -> MoodCheckIn? {
        guard let household = member.household else { return nil }
        let start = calendar.startOfDay(for: day)
        return checkIns(in: household).first { $0.member == member && $0.day == start }
    }

    /// The family's average for a day, or nil if nobody checked in.
    static func average(on day: Date, in household: Household, calendar: Calendar = .current) -> Double? {
        let start = calendar.startOfDay(for: day)
        let ratings = checkIns(in: household).filter { $0.day == start }.map { Double($0.rating) }
        return ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
    }

    /// Daily averages for the last `days` days, oldest first; days nobody checked in are left out.
    static func trend(days: Int = 14, in household: Household, now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, average: Double)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let average = average(on: day, in: household, calendar: calendar) else { return nil }
            return (day, average)
        }
    }

    /// One person's average over the last `days` days, or nil without check-ins.
    static func average(for member: Member, days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let household = member.household,
              let since = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return nil }
        let ratings = checkIns(in: household).filter { $0.member == member && ($0.day ?? .distantPast) >= since }
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0) { $0 + Int($1.rating) }) / Double(ratings.count)
    }
}

extension HouseholdService {
    /// Saves (or changes) today's check-in for this person. Notes are for parents to read.
    @discardableResult
    func checkInMood(_ rating: Int, note: String? = nil, by me: Member, now: Date = Date()) throws -> MoodCheckIn {
        guard FamilyMood.range.contains(rating) else { throw ServiceError.invalid(String(localized: "Pick a face from 1 to 5.")) }
        guard let household = me.household else { throw ServiceError.invalid(String(localized: "Open Happy Mama first to set up your household.")) }
        let mood: MoodCheckIn
        if let existing = FamilyMood.checkIn(by: me, on: now, calendar: calendar) {
            mood = existing
        } else {
            guard let created = NSEntityDescription.insertNewObject(forEntityName: "MoodCheckIn", into: context) as? MoodCheckIn else {
                throw ServiceError.invalid(String(localized: "Couldn't create a \("check-in"). Please try again."))
            }
            if let store = household.objectID.persistentStore { context.assign(created, to: store) }
            created.id = UUID()
            created.day = calendar.startOfDay(for: now)
            created.member = me
            created.household = household
            mood = created
        }
        mood.rating = Int16(rating)
        mood.note = note?.trimmed.nilIfEmpty
        mood.createdAt = now
        try save()
        return mood
    }
}
