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
    /// Problem-solving adds a tenth for each star above one.
    static func suggestedPoints(minutes: Int?, difficulty: Difficulty?, rate: Int, skill: Int? = nil) -> Int? {
        guard minutes != nil || difficulty != nil else { return nil }
        let blocks = (Double(minutes ?? assumedMinutes) / 5).rounded(.up)
        let thinking = 1 + 0.1 * Double(max(0, (skill ?? 1) - 1))
        let points = blocks * Double(max(1, rate)) * (difficulty ?? .medium).multiplier * thinking
        return max(1, Int(points.rounded()))
    }

    /// The chore's "character card": 1 to 5 stars for time, difficulty and problem-solving.
    struct Stars: Equatable {
        var time: Int?
        var difficulty: Int?
        var thinking: Int?
        var isEmpty: Bool { time == nil && difficulty == nil && thinking == nil }
    }

    static func stars(minutes: Int?, difficulty: Difficulty?, skill: Int?) -> Stars {
        let time = minutes.map { m -> Int in
            switch m {
            case ...5: 1
            case ...10: 2
            case ...20: 3
            case ...45: 4
            default: 5
            }
        }
        let hard = difficulty.map { d -> Int in
            switch d {
            case .easy: 1
            case .medium: 3
            case .hard: 5
            }
        }
        return Stars(time: time, difficulty: hard, thinking: skill)
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
