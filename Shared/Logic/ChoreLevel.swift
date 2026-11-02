import Foundation

/// How familiar a kid is with a chore, from how many times they've had it approved.
/// New chores get a little extra encouragement; pros can take on a stretch.
enum ChoreLevel: Equatable {
    case new, learning, pro

    static let learningAfter = 3
    static let proAfter = 10

    init(timesDone: Int) {
        switch timesDone {
        case ..<Self.learningAfter: self = .new
        case ..<Self.proAfter: self = .learning
        default: self = .pro
        }
    }

    var title: String {
        switch self {
        case .new: String(localized: "New to this")
        case .learning: String(localized: "Learning")
        case .pro: String(localized: "Pro")
        }
    }

    var icon: String {
        switch self {
        case .new: "sparkles"
        case .learning: "figure.walk"
        case .pro: "medal"
        }
    }

    /// How many times this chore's kid has had a chore with the same name approved before.
    static func timesDone(_ chore: Chore) -> Int {
        guard let kid = chore.assignee else { return 0 }
        let name = chore.displayTitle
        return ((kid.assignedChores as? Set<Chore>) ?? []).filter {
            $0 !== chore && $0.status == .approved
                && $0.displayTitle.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }.count
    }

    static func of(_ chore: Chore) -> ChoreLevel? {
        chore.assignee == nil ? nil : ChoreLevel(timesDone: timesDone(chore))
    }
}
