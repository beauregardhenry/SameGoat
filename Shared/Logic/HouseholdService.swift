import CoreData

enum ServiceError: LocalizedError {
    case notAllowed(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed(let message), .invalid(let message): message
        }
    }
}

/// All the rules of the app live here: who may do what, and what each action changes.
/// Views call these methods and never mutate chores or points directly.
@MainActor
final class HouseholdService: ObservableObject {
    let persistence: PersistenceController
    var calendar = Calendar.current
    /// Local-only builds give every added member a stand-in sign-in so they can be tested on one device.
    var autoClaimNewMembers: Bool

    var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: PersistenceController, autoClaimNewMembers: Bool = false) {
        self.persistence = persistence
        self.autoClaimNewMembers = autoClaimNewMembers
    }

    // MARK: Household and members

    @discardableResult
    /// Starts a household with you as its first parent, and any kids added during setup.
    func createHousehold(name: String, yourName: String, emoji: String, userID: String,
                         features: Set<Feature> = [], kids: [(name: String, emoji: String)] = []) throws -> Household {
        let name = name.trimmed, yourName = yourName.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid(String(localized: "Give your household a name.")) }
        guard !yourName.isEmpty else { throw ServiceError.invalid(String(localized: "Enter your name.")) }

        let household = try make(Household.self)
        household.id = UUID()
        household.name = name
        household.createdAt = Date()
        household.parentCode = String(format: "%06d", Int.random(in: 0...999_999))
        household.features = features

        let me = try insert(Member.self, into: household)
        me.id = UUID()
        me.name = yourName
        me.role = .parent
        me.emoji = emoji
        me.colorIndex = 0
        me.appleUserID = userID
        me.createdAt = Date()
        me.household = household
        try save()
        for kid in kids where !kid.name.trimmed.isEmpty {
            try addMember(name: kid.name, role: .kid, emoji: kid.emoji, to: household, by: me)
        }
        return household
    }

    @discardableResult
    func addMember(name: String, role: Role, emoji: String, to household: Household, by me: Member) throws -> Member {
        try requireParent(me)
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid(String(localized: "Enter a name.")) }
        let userID = autoClaimNewMembers ? "local-" + UUID().uuidString : nil
        let member = try newMember(name: name, role: role, emoji: emoji, userID: userID, household: household)
        try save()
        return member
    }

    func updateMember(_ member: Member, name: String, role: Role, emoji: String, by me: Member) throws {
        try requireParent(me)
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid(String(localized: "Enter a name.")) }
        if member.role == .parent, role == .kid, (member.household?.parents.count ?? 0) <= 1 {
            throw ServiceError.invalid(String(localized: "A household needs at least one parent."))
        }
        if member.id == me.id, role == .kid {
            throw ServiceError.invalid(String(localized: "You can't make yourself a kid."))
        }
        member.name = name
        member.role = role
        member.emoji = emoji
        try save()
    }

    /// Big picture tiles instead of a list, for kids who can't read much yet.
    func setBigPicture(_ on: Bool, for kid: Member, by me: Member) throws {
        try requireParent(me)
        guard !kid.isParent else { throw ServiceError.invalid(String(localized: "The big picture view is for kids.")) }
        kid.bigPicture = on
        try save()
    }

    func removeMember(_ member: Member, by me: Member) throws {
        try requireParent(me)
        guard member.id != me.id else { throw ServiceError.invalid(String(localized: "You can't remove yourself.")) }
        if member.isParent, (member.household?.parents.count ?? 0) <= 1 {
            throw ServiceError.invalid(String(localized: "A household needs at least one parent."))
        }
        // An up-for-grabs chore this kid had claimed goes back in the pool.
        for chore in (member.assignedChores as? Set<Chore>) ?? [] where chore.upForGrabs && chore.status == .todo {
            chore.assignee = nil
        }
        // A chore kids take turns on passes to whoever is next instead of leaving with this kid.
        for chore in (member.assignedChores as? Set<Chore>) ?? [] where chore.takesTurns && chore.status == .todo {
            guard let next = chore.nextAssignee, next != member else { continue }
            chore.assignee = next
        }
        for chore in (member.household?.chores as? Set<Chore>) ?? [] where chore.rotationIDs.contains(where: { $0 == member.id }) {
            chore.rotationIDs.removeAll { $0 == member.id }
        }
        context.delete(member)
        try save()
    }

    /// Lets someone else pick this profile again (e.g. after a new Apple ID).
    func resetSignIn(of member: Member, by me: Member) throws {
        try requireParent(me)
        guard member.id != me.id else { throw ServiceError.invalid(String(localized: "You can't reset your own sign-in.")) }
        member.appleUserID = nil
        try save()
    }

    /// Lets parents pick a code they'll remember; it unlocks parent profiles
    /// when joining and on a shared family device.
    func setParentCode(_ code: String, for household: Household, by me: Member) throws {
        try requireParent(me)
        let code = code.trimmed
        guard (4...8).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ServiceError.invalid(String(localized: "Use 4 to 8 digits."))
        }
        household.parentCode = code
        try save()
    }

    /// Turns one of the optional features on or off for the whole family.
    func setFeature(_ feature: Feature, on: Bool, for household: Household, by me: Member) throws {
        try requireParent(me)
        var features = household.features
        if on { features.insert(feature) } else { features.remove(feature) }
        household.features = features
        try save()
    }

    /// Links the signed-in iCloud user to an existing profile. Parent profiles
    /// need the household's parent code so a kid can't pick one.
    func claim(_ member: Member, userID: String, parentCode: String?) throws {
        guard member.appleUserID == nil else { throw ServiceError.invalid(String(localized: "Someone has already signed in as \(member.displayName).")) }
        if member.isParent {
            guard let expected = member.household?.parentCode, parentCode?.trimmed == expected else {
                throw ServiceError.notAllowed(String(localized: "That parent code isn't right. A parent can find it under Family."))
            }
        }
        member.appleUserID = userID
        try save()
    }

    @discardableResult
    func joinAsKid(name: String, emoji: String, userID: String, household: Household) throws -> Member {
        let name = name.trimmed
        guard !name.isEmpty else { throw ServiceError.invalid(String(localized: "Enter your name.")) }
        let member = try newMember(name: name, role: .kid, emoji: emoji, userID: userID, household: household)
        try save()
        return member
    }

    private func newMember(name: String, role: Role, emoji: String, userID: String?, household: Household) throws -> Member {
        let member = try insert(Member.self, into: household)
        member.id = UUID()
        member.name = name
        member.role = role
        member.emoji = emoji
        member.colorIndex = Int16(household.memberList.count % Theme.palette.count)
        member.appleUserID = userID
        member.createdAt = Date()
        member.household = household
        return member
    }

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
    private func scheduleNextOccurrence(after chore: Chore) throws {
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

    // MARK: Sync duplicates

    /// Two parents can approve the same chore or reward request on different devices
    /// before either syncs. Each device then records its own point entry and, for a
    /// repeating chore, its own next copy. Balances already count one entry per source;
    /// this deletes the extras so every device ends up with the same records.
    /// The keeper is chosen the same way on every device, so the deletions never collide.
    func resolveSyncDuplicates(in household: Household) throws {
        let entries = (household.entries as? Set<PointEntry>) ?? []
        let keptEntries = Set(PointEntry.unique(entries).map(\.objectID))
        for entry in entries where !keptEntries.contains(entry.objectID) {
            context.delete(entry)
        }

        let copies = ((household.chores as? Set<Chore>) ?? []).filter { $0.sourceChoreID != nil }
        for group in Dictionary(grouping: copies, by: \.sourceChoreID).values where group.count > 1 {
            // Keep the copy the kid has made the most progress on.
            let keeper = group.max { a, b in
                a.status.progress != b.status.progress ? a.status.progress < b.status.progress : syncOrder(b, a)
            }
            for chore in group where chore !== keeper {
                context.delete(chore)
            }
        }

        // Two devices checking in the same person for the same day: keep the one that counts.
        let keptMoods = Set(FamilyMood.checkIns(in: household).map(\.objectID))
        for mood in (household.moods as? Set<MoodCheckIn>) ?? [] where !keptMoods.contains(mood.objectID) {
            context.delete(mood)
        }
        try save()
    }

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

    // MARK: Helpers

    private func addEntry(_ amount: Int32, kind: EntryKind, reason: String, to kid: Member,
                          in household: Household) throws -> PointEntry {
        let entry = try insert(PointEntry.self, into: household)
        entry.id = UUID()
        entry.amount = amount
        entry.reason = reason
        entry.kind = kind
        entry.date = Date()
        entry.member = kid
        entry.household = household
        return entry
    }

    private func requireParent(_ me: Member) throws {
        guard me.isParent else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
    }

    private func make<T: NSManagedObject>(_ type: T.Type) throws -> T {
        let name = String(describing: type)
        guard let object = NSEntityDescription.insertNewObject(forEntityName: name, into: context) as? T else {
            throw ServiceError.invalid(String(localized: "Couldn't create a \(name). Please try again."))
        }
        return object
    }

    /// New objects must land in the same store as their household, otherwise
    /// something created by an invited person would stay out of the shared database.
    private func insert<T: NSManagedObject>(_ type: T.Type, into household: Household) throws -> T {
        let object = try make(type)
        if let store = household.objectID.persistentStore {
            context.assign(object, to: store)
        }
        return object
    }

    func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
