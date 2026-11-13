import CoreData

// Creating, editing and deleting chores, and the rules that repeat them.
extension HouseholdService {
    // MARK: Chores

    struct ChoreDraft {
        var title = ""
        var notes = ""
        var points = 10
        var dueDate: Date?
        /// Minutes after midnight on the due date; nil means any time that day.
        var dueTime: Int?
        var recurrence = RecurrenceRule()
        /// One chore that moves to the next kid each time it repeats, instead of a copy each.
        var takeTurns = false
        /// Award the points as soon as the kid marks it done, without a parent checking.
        var autoApprove = false
        /// A routine's checklist; empty for an ordinary chore.
        var steps: [String] = []
        /// The kid has to attach a photo to turn it in.
        var photoRequired = false
        /// About how long it takes, and how hard it is, for suggesting fair points.
        var minutes: Int?
        var difficulty: Difficulty?
        /// Nobody is assigned: any kid can claim it or just do it.
        var upForGrabs = false
        var timeOfDay: TimeOfDay?
        var emoji: String?
        var whyItHelps = ""
        var tips = ""
        /// Problem-solving stars, 1 to 5.
        var skill: Int?
        var stretch = false
        var extraCredit = false
        /// Due by the end of the week of `dueDate` (or this week) rather than on that day.
        var dueWithinWeek = false
        /// Energy in spoons, 1 to 3; nil goes by the difficulty.
        var spoons: Int?
    }

    static let maxSteps = 12

    /// Gives each kid their own copy, or with `takeTurns` one chore the kids take turns on,
    /// starting with the first of `assignees`.
    @discardableResult
    func createChores(_ draft: ChoreDraft, assignees: [Member], in household: Household, by me: Member,
                      saving: Bool = true) throws -> [Chore] {
        try requireParent(me)
        if draft.upForGrabs {
            let title = try validated(draft, assignees: [])
            let chore = try newChore(from: draft, title: title, assignee: nil, household: household)
            if saving { try save() }
            return [chore]
        }
        guard let first = assignees.first else { throw ServiceError.invalid(String(localized: "Choose who should do it.")) }
        let title = try validated(draft, assignees: assignees)
        if draft.takeTurns {
            let chore = try newChore(from: draft, title: title, assignee: first, household: household)
            chore.rotationIDs = assignees.compactMap(\.id)
            if saving { try save() }
            return [chore]
        }
        let created = try assignees.map { member in
            let chore = try newChore(from: draft, title: title, assignee: member, household: household)
            // Grown-ups pitch in too, but their chores don't earn points.
            if member.isParent { chore.points = 0 }
            return chore
        }
        if saving { try save() }
        return created
    }

    func updateChore(_ chore: Chore, with draft: ChoreDraft, assignee: Member, by me: Member) throws {
        try updateChore(chore, with: draft, assignees: [assignee], by: me)
    }

    /// `assignees` is the one kid doing it, or with `takeTurns` everyone taking turns. The kid
    /// whose turn it is keeps it if they're still in the rotation.
    func updateChore(_ chore: Chore, with draft: ChoreDraft, assignees: [Member], by me: Member) throws {
        try requireParent(me)
        guard chore.status == .todo else { throw ServiceError.invalid(String(localized: "Only chores that haven't been turned in can be edited.")) }
        if draft.upForGrabs {
            // Turning a chore into an up-for-grabs one puts it in the pool; editing one keeps its claim.
            let title = try validated(draft, assignees: [])
            apply(draft, title: title, to: chore)
            if !chore.upForGrabs { chore.assignee = nil }
            chore.upForGrabs = true
            chore.rotationIDs = []
            try save()
            return
        }
        guard let first = assignees.first else { throw ServiceError.invalid(String(localized: "Choose who should do it.")) }
        guard draft.takeTurns || assignees.count == 1 else { throw ServiceError.invalid(String(localized: "Choose one person, or let them take turns.")) }
        let title = try validated(draft, assignees: assignees)
        apply(draft, title: title, to: chore)
        chore.upForGrabs = false
        chore.rotationIDs = draft.takeTurns ? assignees.compactMap(\.id) : []
        let assignee = assignees.first { $0.id == chore.assignee?.id } ?? first
        if chore.assignee?.id != assignee.id {
            chore.assignee = assignee
            chore.reviewNote = nil
        }
        if assignee.isParent { chore.points = 0 }
        try save()
    }

    func deleteChore(_ chore: Chore, by me: Member) throws {
        try requireParent(me)
        context.delete(chore)
        try save()
    }

    /// A kid says they're done. Nothing is awarded until a parent confirms.

    func endOfWeek(containing date: Date) -> Date {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 6, to: start) ?? start
    }

    /// The fields editing can change, shared by every kind of assignment.
    private func apply(_ draft: ChoreDraft, title: String, to chore: Chore) {
        chore.title = title
        chore.notes = draft.notes.trimmed
        chore.points = Int32(max(0, draft.points))
        if draft.dueWithinWeek {
            chore.dueDate = endOfWeek(containing: draft.dueDate ?? Date())
            chore.dueTime = nil
        } else {
            chore.dueDate = draft.dueDate.map { calendar.startOfDay(for: $0) }
            chore.dueTime = draft.dueDate == nil ? nil : draft.dueTime
        }
        chore.dueWithinWeek = draft.dueWithinWeek
        chore.autoApprove = draft.autoApprove
        chore.photoRequired = draft.photoRequired
        chore.minutes = draft.minutes
        chore.difficulty = draft.difficulty
        chore.timeOfDay = draft.timeOfDay
        chore.emoji = draft.emoji?.trimmed.nilIfEmpty
        chore.whyItHelps = draft.whyItHelps.trimmed.nilIfEmpty
        chore.tips = draft.tips.trimmed.nilIfEmpty
        chore.skill = draft.skill
        chore.stretch = draft.stretch
        chore.extraCredit = draft.extraCredit
        chore.spoonsRaw = Int16(draft.spoons.map { min(max($0, 1), Spoons.range.upperBound) } ?? 0)
        let oldSteps = chore.steps
        chore.steps = draft.steps
        if chore.steps != oldSteps { chore.doneSteps = [] }
        chore.recurrence = draft.recurrence
    }

    /// Returns the trimmed title once the draft passes the rules shared by creating and editing.
    private func validated(_ draft: ChoreDraft, assignees: [Member]) throws -> String {
        let title = draft.title.trimmed
        guard !title.isEmpty else { throw ServiceError.invalid(String(localized: "Give the chore a title.")) }
        if draft.recurrence.isRepeating, draft.dueDate == nil {
            throw ServiceError.invalid(String(localized: "Repeating chores need a due date to start from."))
        }
        if let minutes = draft.minutes, !Effort.minuteRange.contains(minutes) {
            throw ServiceError.invalid(String(localized: "Use between 1 and 600 minutes."))
        }
        guard draft.steps.filter({ !$0.trimmed.isEmpty }).count <= Self.maxSteps else {
            throw ServiceError.invalid(String(localized: "A routine can have up to \(Self.maxSteps) steps."))
        }
        if draft.takeTurns && !draft.upForGrabs {
            guard assignees.allSatisfy({ !$0.isParent }) else {
                throw ServiceError.invalid(String(localized: "Taking turns is for kids."))
            }
            guard assignees.count > 1 else { throw ServiceError.invalid(String(localized: "Choose at least two kids to take turns.")) }
            guard draft.recurrence.isRepeating else { throw ServiceError.invalid(String(localized: "Taking turns needs a chore that repeats.")) }
        }
        return title
    }

    /// A nil assignee means the chore is up for grabs.
    private func newChore(from draft: ChoreDraft, title: String, assignee: Member?, household: Household) throws -> Chore {
        let chore = try insert(Chore.self, into: household)
        chore.id = UUID()
        apply(draft, title: title, to: chore)
        chore.status = .todo
        chore.createdAt = Date()
        chore.upForGrabs = assignee == nil
        chore.household = household
        chore.assignee = assignee
        return chore
    }

    /// Repeating chores get their next copy once the current one is approved; if kids
    /// take turns, it goes to whoever is next.
    func scheduleNextOccurrence(after chore: Chore) throws {
        let rule = chore.recurrence
        guard rule.isRepeating, let household = chore.household else { return }
        // An up-for-grabs chore goes back in the pool; others go to whoever's next.
        let kid = chore.upForGrabs ? nil : chore.nextAssignee
        guard chore.upForGrabs || kid != nil else { return }
        // Late chores repeat from today, not from the missed date.
        let base = max(chore.dueDate ?? Date(), calendar.startOfDay(for: Date()))
        guard var next = rule.nextDate(after: base, calendar: calendar) else { return }
        // Skip over a vacation pause rather than piling chores up for the trip.
        while household.isPaused(on: next, calendar: calendar), let later = rule.nextDate(after: next, calendar: calendar) {
            next = later
        }
        var draft = ChoreDraft()
        draft.notes = chore.notes ?? ""
        draft.points = Int(chore.points)
        draft.dueDate = next
        draft.dueTime = chore.dueTime
        draft.autoApprove = chore.autoApprove
        draft.steps = chore.steps
        draft.photoRequired = chore.photoRequired
        draft.minutes = chore.minutes
        draft.difficulty = chore.difficulty
        draft.timeOfDay = chore.timeOfDay
        draft.emoji = chore.emoji
        draft.whyItHelps = chore.whyItHelps ?? ""
        draft.tips = chore.tips ?? ""
        draft.skill = chore.skill
        draft.stretch = chore.stretch
        draft.extraCredit = chore.extraCredit
        draft.dueWithinWeek = chore.dueWithinWeek
        draft.spoons = chore.spoonsRaw > 0 ? Int(chore.spoonsRaw) : nil
        draft.recurrence = rule
        let copy = try newChore(from: draft, title: chore.displayTitle, assignee: kid, household: household)
        copy.sourceChoreID = chore.id
        copy.rotationIDs = chore.rotationIDs
    }
}
