import CoreData

// A chore's life after it is assigned: doing it, turning it in, and the parent's verdict.
extension HouseholdService {
    func markComplete(_ chore: Chore, by me: Member, note: String?, photo: Data?) throws {
        // Nobody had claimed it, so the kid who did it gets the credit.
        if chore.isUnclaimed, !me.isParent, chore.status == .todo { chore.assignee = me }
        // A grown-up's own chore is simply done: there's nobody to check it and no points.
        if me.isParent, chore.assignee?.id == me.id {
            guard chore.status == .todo else { throw ServiceError.invalid(String(localized: "This chore was already turned in.")) }
            chore.status = .approved
            chore.completedAt = Date()
            chore.reviewedAt = Date()
            chore.awardedPoints = 0
            try scheduleNextOccurrence(after: chore)
            finishProjectIfDone(for: chore)
            try save()
            return
        }
        guard chore.assignee?.id == me.id, !me.isParent else {
            throw ServiceError.notAllowed(String(localized: "Only the person a chore is assigned to can mark it done."))
        }
        guard chore.status == .todo else { throw ServiceError.invalid(String(localized: "This chore was already turned in.")) }
        // Doing one of the menu's options counts as choosing it.
        if chore.isMenuOption { try pick(chore, by: me) }
        guard chore.allStepsDone else { throw ServiceError.invalid(String(localized: "Tick off every step first.")) }
        guard !chore.photoRequired || photo != nil else { throw ServiceError.invalid(String(localized: "Add a photo to show it's done.")) }
        chore.status = .pendingReview
        chore.completedAt = Date()
        chore.completionNote = note?.trimmed.nilIfEmpty
        chore.photo = photo
        chore.reviewNote = nil
        // Parents can trust small habits to count right away.
        if chore.autoApprove { try award(chore, points: Int(chore.points), reviewer: nil) }
        try save()
    }

    /// A kid calls dibs on an up-for-grabs chore so nobody else does it.
    func claim(_ chore: Chore, by me: Member) throws {
        guard !me.isParent else { throw ServiceError.notAllowed(String(localized: "Only kids claim chores.")) }
        guard chore.isUnclaimed, chore.status == .todo else {
            throw ServiceError.invalid(String(localized: "Someone already took this one."))
        }
        chore.assignee = me
        try save()
    }

    /// Puts a claimed chore back in the pool, by the kid who claimed it or a parent.
    func release(_ chore: Chore, by me: Member) throws {
        guard chore.upForGrabs, chore.status == .todo, let holder = chore.assignee else {
            throw ServiceError.invalid(String(localized: "This chore isn't claimed."))
        }
        guard me.isParent || holder.id == me.id else { throw ServiceError.notAllowed(String(localized: "This isn't your chore.")) }
        chore.assignee = nil
        chore.doneSteps = []
        try save()
    }

    /// When life gets in the way, a parent passes a take-turns chore to whoever's next.
    func skipTurn(_ chore: Chore, by me: Member) throws {
        try requireParent(me)
        guard chore.takesTurns, chore.status == .todo else {
            throw ServiceError.invalid(String(localized: "Only a chore kids take turns on can skip a turn."))
        }
        guard let next = chore.nextAssignee, next != chore.assignee else { throw ServiceError.invalid(String(localized: "There's nobody else to take a turn.")) }
        chore.assignee = next
        chore.doneSteps = []
        chore.reviewNote = nil
        try save()
    }

    static let nudgeInterval: TimeInterval = 10 * 60

    /// A parent reminds a kid about a chore; their device shows it as a notification.
    func nudge(_ chore: Chore, by me: Member, now: Date = Date()) throws {
        try requireParent(me)
        guard chore.status == .todo, chore.assignee != nil else {
            throw ServiceError.invalid(String(localized: "Only a chore someone still has to do can get a reminder."))
        }
        if let last = chore.nudgedAt, now.timeIntervalSince(last) < Self.nudgeInterval {
            throw ServiceError.invalid(String(localized: "You just sent a reminder. Give it a few minutes."))
        }
        chore.nudgedAt = now
        chore.nudgedByName = me.name
        try save()
    }

    /// Once a day a kid can push one of today's chores to tomorrow, no questions asked.
    /// After that, they push through. It gives a real choice while still encouraging trying.
    func useResetPass(on chore: Chore, by me: Member, now: Date = Date()) throws {
        guard !me.isParent, chore.assignee?.id == me.id, chore.status == .todo else {
            throw ServiceError.notAllowed(String(localized: "This isn't your chore."))
        }
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let due = chore.dueDate, due < tomorrow else {
            throw ServiceError.invalid(String(localized: "The reset pass is for chores due today."))
        }
        guard me.household?.has(.energy) == true else {
            throw ServiceError.invalid(String(localized: "Turn on Energy and reset pass under Family → Features first."))
        }
        if let used = me.resetUsedOn, calendar.isDate(used, inSameDayAs: now) {
            throw ServiceError.invalid(String(localized: "You've used today's reset pass. You've got this!"))
        }
        chore.dueDate = tomorrow
        me.resetUsedOn = today
        try save()
    }

    /// A kid ticks or unticks one step of a routine.
    func toggleStep(_ index: Int, of chore: Chore, by me: Member) throws {
        guard chore.assignee?.id == me.id, !me.isParent else { throw ServiceError.notAllowed(String(localized: "This isn't your routine.")) }
        guard chore.status == .todo else { throw ServiceError.invalid(String(localized: "This routine was already turned in.")) }
        guard chore.steps.indices.contains(index) else { throw ServiceError.invalid(String(localized: "That step is gone.")) }
        var done = chore.doneSteps
        if done.contains(index) { done.remove(index) } else { done.insert(index) }
        chore.doneSteps = done
        try save()
    }

    /// Takes a turned-in chore back before a parent has looked at it.
    func withdraw(_ chore: Chore, by me: Member) throws {
        guard chore.assignee?.id == me.id else { throw ServiceError.notAllowed(String(localized: "This isn't your chore.")) }
        guard chore.status == .pendingReview else { throw ServiceError.invalid(String(localized: "This chore isn't waiting for approval.")) }
        chore.status = .todo
        chore.completedAt = nil
        chore.completionNote = nil
        chore.photo = nil
        try save()
    }

    /// A parent confirms the chore. This and auto-approved chores are the only ways
    /// chore points are awarded. `points` overrides the chore's value (partial or bonus credit).
    func approve(_ chore: Chore, by me: Member, points: Int? = nil) throws {
        try requireParent(me)
        guard chore.status == .pendingReview else { throw ServiceError.invalid(String(localized: "This chore isn't waiting for approval.")) }
        try award(chore, points: points ?? Int(chore.points), reviewer: me.name)
        try save()
    }

    /// Marks the chore approved, records its points, and schedules a repeating chore's
    /// next copy. A nil reviewer means it was approved automatically.
    private func award(_ chore: Chore, points: Int, reviewer: String?) throws {
        guard let kid = chore.assignee, let household = chore.household else { throw ServiceError.invalid(String(localized: "This chore has no owner.")) }
        let awarded = max(0, points)
        chore.status = .approved
        chore.awardedPoints = Int32(awarded)
        chore.reviewedAt = Date()
        chore.reviewedByName = reviewer
        chore.reviewNote = nil

        let entry = try addEntry(Int32(awarded), kind: .chore, reason: chore.displayTitle, to: kid, in: household)
        entry.choreID = chore.id

        try scheduleNextOccurrence(after: chore)
        finishProjectIfDone(for: chore)
    }

    /// A parent sends the chore back to the kid with a note. No points are awarded.
    func reject(_ chore: Chore, by me: Member, note: String) throws {
        try requireParent(me)
        guard chore.status == .pendingReview else { throw ServiceError.invalid(String(localized: "This chore isn't waiting for approval.")) }
        chore.status = .todo
        chore.reviewNote = note.trimmed.nilIfEmpty ?? String(localized: "Please take another look.")
        chore.reviewedAt = Date()
        chore.reviewedByName = me.name
        chore.completedAt = nil
        chore.completionNote = nil
        chore.photo = nil
        try save()
    }

    /// The last day of the week that `date` falls in, by the household's calendar.
}
