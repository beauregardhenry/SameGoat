import Foundation

/// How hard a chore is, which scales the points it suggests.
enum Difficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: String(localized: "Easy")
        case .medium: String(localized: "Medium")
        case .hard: String(localized: "Hard")
        }
    }

    var multiplier: Double {
        switch self {
        case .easy: 1
        case .medium: 1.5
        case .hard: 2
        }
    }
}

/// Weighs a chore by how long it takes and how hard it is, so points can be fair
/// without a parent working them out each time.
enum Effort {
    static let timeChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120]
    static let minuteRange = 1...600
    static let rateRange = 1...20
    /// When only a difficulty is set, assume a quick ten-minute job.
    static let assumedMinutes = 10

    /// `rate` points for every 5 minutes (rounded up), times the difficulty. Nil with no effort set.
    static func suggestedPoints(minutes: Int?, difficulty: Difficulty?, rate: Int) -> Int? {
        guard minutes != nil || difficulty != nil else { return nil }
        let blocks = (Double(minutes ?? assumedMinutes) / 5).rounded(.up)
        let points = blocks * Double(max(1, rate)) * (difficulty ?? .medium).multiplier
        return max(1, Int(points.rounded()))
    }

    /// "15 min · Hard", "15 min", "Hard", or nil.
    static func label(minutes: Int?, difficulty: Difficulty?) -> String? {
        let parts = [minutes.map { String(localized: "\($0) min") }, difficulty?.title].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Minutes of chores a kid still has to do in the coming week (undated ones included),
    /// for balancing who gets the next one.
    static func openMinutes(for kid: Member, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let weekOut = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return ((kid.assignedChores as? Set<Chore>) ?? [])
            .filter { $0.status == .todo && ($0.dueDate ?? .distantPast) < weekOut }
            .reduce(0) { $0 + ($1.minutes ?? 0) }
    }
}
