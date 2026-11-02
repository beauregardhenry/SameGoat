import CoreData

enum Role: String, CaseIterable, Identifiable {
    case parent, kid
    var id: String { rawValue }
    var title: String { self == .parent ? String(localized: "Parent") : String(localized: "Kid") }
}

enum ChoreStatus: String {
    case todo, pendingReview, approved

    /// How far along the chore is, for picking between duplicates.
    var progress: Int {
        switch self {
        case .todo: 0
        case .pendingReview: 1
        case .approved: 2
        }
    }
}

/// When in the day a chore belongs, so a kid's list reads like their day.
enum TimeOfDay: String, CaseIterable, Identifiable {
    case morning, afternoon, evening
    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: String(localized: "Morning")
        case .afternoon: String(localized: "Afternoon")
        case .evening: String(localized: "Evening")
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "moon.stars"
        }
    }
}

enum RedemptionStatus: String {
    case requested, approved, denied
}

enum EntryKind: String {
    /// `bonus` is points a parent gives with a reason, outside any chore;
    /// `payout` is points turned into pocket money.
    case chore, redemption, bonus, payout
}

@objc(Household)
final class Household: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var parentCode: String?
    @NSManaged var createdAt: Date?
    @NSManaged var members: NSSet?
    @NSManaged var chores: NSSet?
    @NSManaged var rewards: NSSet?
    @NSManaged var redemptions: NSSet?
    @NSManaged var entries: NSSet?
    @NSManaged var projects: NSSet?
    /// Allowance mode: how many points make one unit of money (one dollar, one euro). 0 is off.
    @NSManaged var allowanceRate: Int16
    @NSManaged var currencyCode: String?
    /// A vacation pause, first and last day included (start-of-day dates).
    @NSManaged var pausedFrom: Date?
    @NSManaged var pausedUntil: Date?
    /// Points suggested for every 5 minutes of a chore, before difficulty.
    @NSManaged var effortRate: Int16

    var displayName: String { name ?? String(localized: "Our Household") }
    var allowanceOn: Bool { allowanceRate > 0 }

    /// Projects still underway, soonest due first.
    func activeProjects(now: Date = Date(), calendar: Calendar = .current) -> [Project] {
        ((projects as? Set<Project>) ?? [])
            .filter { $0.isActive(now: now, calendar: calendar) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// The project that's putting regular chores on hold right now, if any.
    func overridingProject(now: Date = Date(), calendar: Calendar = .current) -> Project? {
        activeProjects(now: now, calendar: calendar).first(where: \.pausesRegular)
    }

    /// True on any day of the vacation pause.
    func isPaused(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let pausedFrom, let pausedUntil else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: pausedFrom) && day <= calendar.startOfDay(for: pausedUntil)
    }

    /// A pause that hasn't finished yet, for the banner and settings.
    func upcomingPause(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let pausedFrom, let pausedUntil, calendar.startOfDay(for: pausedUntil) >= calendar.startOfDay(for: now) else { return nil }
        return pausedFrom...pausedUntil
    }

    /// What `points` are worth in money, or nil with allowance mode off.
    func money(for points: Int) -> Decimal? {
        guard allowanceOn else { return nil }
        return Decimal(points) / Decimal(Int(allowanceRate))
    }

    /// "$2.40", or nil with allowance mode off.
    func moneyText(for points: Int, locale: Locale = .current) -> String? {
        money(for: points)?.formatted(.currency(code: currencyCode ?? "USD").locale(locale))
    }
    var memberList: [Member] {
        ((members as? Set<Member>) ?? []).sorted {
            if $0.isParent != $1.isParent { return $0.isParent }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    var kids: [Member] { memberList.filter { !$0.isParent } }
    var parents: [Member] { memberList.filter { $0.isParent } }
}

@objc(Member)
final class Member: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var roleRaw: String?
    @NSManaged var emoji: String?
    @NSManaged var colorIndex: Int16
    @NSManaged var appleUserID: String?
    @NSManaged var createdAt: Date?
    /// The reward a kid is saving toward.
    @NSManaged var goalRewardID: UUID?
    /// The day a kid last used their reset pass (one chore pushed to tomorrow, once a day).
    @NSManaged var resetUsedOn: Date?
    /// Shows this kid big picture tiles instead of a list, for little ones.
    @NSManaged var bigPicture: Bool
    @NSManaged var household: Household?
    @NSManaged var assignedChores: NSSet?
    @NSManaged var redemptions: NSSet?
    @NSManaged var entries: NSSet?

    var role: Role {
        get { Role(rawValue: roleRaw ?? "") ?? .kid }
        set { roleRaw = newValue.rawValue }
    }
    var isParent: Bool { role == .parent }
    var displayName: String { name ?? String(localized: "Someone") }
    var displayEmoji: String { emoji ?? (isParent ? "🌻" : "🦊") }
    var isClaimed: Bool { appleUserID != nil }

    /// Newest first. Two parents acting on the same chore or request from different
    /// devices can each record an entry before they sync, so only one per source counts.
    var entryList: [PointEntry] {
        PointEntry.unique((entries as? Set<PointEntry>) ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    /// Points earned minus points spent.
    var balance: Int { entryList.reduce(0) { $0 + Int($1.amount) } }
    /// Points tied up in redemption requests a parent hasn't decided yet.
    var reserved: Int {
        ((redemptions as? Set<Redemption>) ?? [])
            .filter { $0.status == .requested }
            .reduce(0) { $0 + Int($1.cost) }
    }
    var available: Int { balance - reserved }

    /// The reward this kid is saving for, while it's still offered.
    var goal: Reward? {
        guard let goalRewardID else { return nil }
        return ((household?.rewards as? Set<Reward>) ?? []).first { $0.id == goalRewardID && $0.isActive }
    }
    /// How close `available` is to the goal, from 0 to 1.
    var goalProgress: Double {
        guard let cost = goal?.cost, cost > 0 else { return 0 }
        return min(1, Double(max(0, available)) / Double(cost))
    }

    /// Days in a row on which this kid turned in a chore that wasn't sent back, ending
    /// today or yesterday. Yesterday still counts so the streak doesn't read 0 every morning.
    func streak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(((assignedChores as? Set<Chore>) ?? []).compactMap { chore -> Date? in
            guard chore.status != .todo, let done = chore.completedAt else { return nil }
            return calendar.startOfDay(for: done)
        })
        // Vacation days neither count nor break the streak.
        let paused = { (day: Date) in self.household?.isPaused(on: day, calendar: calendar) == true && !days.contains(day) }
        var day = calendar.startOfDay(for: now)
        func back(_ date: Date) -> Date? { calendar.date(byAdding: .day, value: -1, to: date) }
        while paused(day), let previous = back(day) { day = previous }
        if !days.contains(day), let yesterday = back(day) {
            day = yesterday
            while paused(day), let previous = back(day) { day = previous }
        }
        var count = 0
        while days.contains(day), let previous = back(day) {
            count += 1
            day = previous
            while paused(day), let earlier = back(day) { day = earlier }
        }
        return count
    }
}

@objc(Chore)
final class Chore: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var notes: String?
    @NSManaged var points: Int32
    @NSManaged var statusRaw: String?
    @NSManaged var dueDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var recurrenceRaw: String?
    @NSManaged var weekdayMask: Int16
    @NSManaged var completedAt: Date?
    @NSManaged var completionNote: String?
    @NSManaged var photo: Data?
    @NSManaged var reviewedAt: Date?
    @NSManaged var reviewedByName: String?
    @NSManaged var reviewNote: String?
    @NSManaged var awardedPoints: Int32
    /// For a repeating chore's next copy: the chore whose approval created it.
    @NSManaged var sourceChoreID: UUID?
    /// For a chore kids take turns on: the member ids in turn order, comma-separated.
    @NSManaged var rotationRaw: String?
    /// Minutes after midnight the chore is due by, or -1 for any time that day.
    @NSManaged var dueMinute: Int16
    /// Points are awarded as soon as the kid marks it done.
    @NSManaged var autoApprove: Bool
    /// For a routine: its steps, one per line.
    @NSManaged var stepsRaw: String?
    /// Which steps (by position) the kid has ticked, comma-separated.
    @NSManaged var doneStepsRaw: String?
    /// The kid has to attach a photo to turn it in.
    @NSManaged var photoRequired: Bool
    /// About how long it takes, in minutes; 0 when not set.
    @NSManaged var minutesRaw: Int16
    @NSManaged var difficultyRaw: String?
    /// Open to every kid: whoever claims or finishes it first gets it.
    @NSManaged var upForGrabs: Bool
    @NSManaged var timeOfDayRaw: String?
    /// A picture for kids who can't read yet.
    @NSManaged var emoji: String?
    /// The last time a parent sent a reminder about it, and who.
    @NSManaged var nudgedAt: Date?
    @NSManaged var nudgedByName: String?
    /// How this chore helps the whole family, in a sentence kids can read.
    @NSManaged var whyItHelps: String?
    /// Parents' advice for doing it faster or better, so kids hear it from the app.
    @NSManaged var tips: String?
    /// How much problem-solving it takes, 1 to 5 stars; 0 when not set.
    @NSManaged var skillRaw: Int16
    /// A step up from what this kid usually does.
    @NSManaged var stretch: Bool
    /// Optional: earns points but is never owed, so it never goes overdue.
    @NSManaged var extraCredit: Bool
    /// Due any day this week rather than on one day.
    @NSManaged var dueWithinWeek: Bool
    /// Set for a chore that's part of a project, with the project step it belongs to.
    @NSManaged var projectID: UUID?
    @NSManaged var phase: Int16
    /// How much energy it takes, 1 to 3 spoons; 0 means "go by the difficulty".
    @NSManaged var spoonsRaw: Int16
    /// A choice menu: the kid picks `menuPick` of the chores sharing this id.
    @NSManaged var menuID: UUID?
    @NSManaged var menuPick: Int16
    @NSManaged var menuPicked: Bool
    /// When picked, it was the easiest option left, for spotting a kid who always goes easy.
    @NSManaged var menuEasiest: Bool

    /// Still one of the options on offer: not chosen yet, so not owed.
    var isMenuOption: Bool { menuID != nil && !menuPicked }

    var spoons: Int {
        get {
            if spoonsRaw > 0 { return Int(spoonsRaw) }
            switch difficulty {
            case .easy: return 1
            case .hard: return 3
            case .medium, nil: return 2
            }
        }
        set { spoonsRaw = Int16(min(max(newValue, 0), Spoons.range.upperBound)) }
    }

    var project: Project? {
        guard let projectID else { return nil }
        return ((household?.projects as? Set<Project>) ?? []).first { $0.id == projectID }
    }
    /// A regular chore set aside while a project that comes first is underway.
    func isOnHold(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        projectID == nil && household?.overridingProject(now: now, calendar: calendar) != nil
    }

    var skill: Int? {
        get { skillRaw > 0 ? Int(skillRaw) : nil }
        set { skillRaw = Int16(newValue.map { min(max($0, 0), 5) } ?? 0) }
    }

    /// Still in the pool: nobody has claimed it yet.
    var isUnclaimed: Bool { upForGrabs && assignee == nil }
    var timeOfDay: TimeOfDay? {
        get { timeOfDayRaw.flatMap(TimeOfDay.init(rawValue:)) }
        set { timeOfDayRaw = newValue?.rawValue }
    }
    /// A chore worth no points is a family job: done because we live here.
    var isFamilyJob: Bool { points == 0 }

    var minutes: Int? {
        get { minutesRaw > 0 ? Int(minutesRaw) : nil }
        set { minutesRaw = Int16(newValue.map { min(max($0, 0), Effort.minuteRange.upperBound) } ?? 0) }
    }
    var difficulty: Difficulty? {
        get { difficultyRaw.flatMap(Difficulty.init(rawValue:)) }
        set { difficultyRaw = newValue?.rawValue }
    }
    var effortLabel: String? { Effort.label(minutes: minutes, difficulty: difficulty) }
    @NSManaged var household: Household?
    @NSManaged var assignee: Member?

    var rotationIDs: [UUID] {
        get { (rotationRaw ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { rotationRaw = newValue.isEmpty ? nil : newValue.map(\.uuidString).joined(separator: ",") }
    }
    /// The kids taking turns who are still in the household, in turn order.
    var rotation: [Member] {
        let kids = household?.kids ?? []
        return rotationIDs.compactMap { id in kids.first { $0.id == id } }
    }
    var takesTurns: Bool { rotationIDs.count > 1 }
    /// Who the next copy goes to: the next kid in the rotation, or the same kid if there's no one else.
    var nextAssignee: Member? {
        let kids = rotation
        guard kids.count > 1 else { return kids.first ?? assignee }
        guard let assignee, let index = kids.firstIndex(of: assignee) else { return kids.first }
        return kids[(index + 1) % kids.count]
    }

    var displayTitle: String { title ?? String(localized: "Chore") }
    var status: ChoreStatus {
        get { ChoreStatus(rawValue: statusRaw ?? "") ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
    var recurrence: RecurrenceRule {
        get { RecurrenceRule(kind: Recurrence(rawValue: recurrenceRaw ?? "") ?? .none, weekdayMask: Int(weekdayMask)) }
        set { recurrenceRaw = newValue.kind.rawValue; weekdayMask = Int16(newValue.weekdayMask) }
    }
    /// The time of day it's due by, in minutes after midnight, if a parent set one.
    var dueTime: Int? {
        get { dueMinute >= 0 ? Int(dueMinute) : nil }
        set { dueMinute = Int16(newValue.map { min(max($0, 0), 24 * 60 - 1) } ?? -1) }
    }
    /// The moment it's due: the due time on the due date, or the end of that day.
    func dueAt(calendar: Calendar = .current) -> Date? {
        guard let dueDate else { return nil }
        let day = calendar.startOfDay(for: dueDate)
        if let dueTime { return calendar.date(byAdding: .minute, value: dueTime, to: day) }
        return calendar.date(byAdding: .day, value: 1, to: day)
    }
    var isOverdue: Bool { isOverdue() }
    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status == .todo, !extraCredit, !isMenuOption, let due = dueAt(calendar: calendar) else { return false }
        // Regular chores wait while a project that comes first is underway.
        if isOnHold(now: now, calendar: calendar) { return false }
        // Nothing goes overdue during a vacation, or for being due on one.
        if let household, household.isPaused(on: now, calendar: calendar)
            || dueDate.map({ household.isPaused(on: $0, calendar: calendar) }) == true { return false }
        return due <= now
    }
    var wasSentBack: Bool { status == .todo && !(reviewNote ?? "").isEmpty }

    var steps: [String] {
        get { (stepsRaw ?? "").split(separator: "\n").map(String.init) }
        set {
            let clean = newValue.map { $0.replacingOccurrences(of: "\n", with: " ").trimmed }.filter { !$0.isEmpty }
            stepsRaw = clean.isEmpty ? nil : clean.joined(separator: "\n")
        }
    }
    var doneSteps: Set<Int> {
        get { Set((doneStepsRaw ?? "").split(separator: ",").compactMap { Int($0) }.filter { steps.indices.contains($0) }) }
        set { doneStepsRaw = newValue.isEmpty ? nil : newValue.sorted().map(String.init).joined(separator: ",") }
    }
    var isRoutine: Bool { !steps.isEmpty }
    var allStepsDone: Bool { doneSteps.count == steps.count }
}

@objc(Reward)
final class Reward: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var emoji: String?
    @NSManaged var cost: Int32
    @NSManaged var isActive: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?

    var displayTitle: String { title ?? String(localized: "Reward") }
    var displayEmoji: String { emoji ?? "🎁" }
}

@objc(Redemption)
final class Redemption: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var rewardTitle: String?
    @NSManaged var rewardEmoji: String?
    @NSManaged var cost: Int32
    @NSManaged var statusRaw: String?
    @NSManaged var requestedAt: Date?
    @NSManaged var decidedAt: Date?
    @NSManaged var decidedByName: String?
    @NSManaged var household: Household?
    @NSManaged var member: Member?

    var status: RedemptionStatus {
        get { RedemptionStatus(rawValue: statusRaw ?? "") ?? .requested }
        set { statusRaw = newValue.rawValue }
    }
    var displayTitle: String { rewardTitle ?? String(localized: "Reward") }
    var displayEmoji: String { rewardEmoji ?? "🎁" }
}

@objc(PointEntry)
final class PointEntry: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var amount: Int32
    @NSManaged var reason: String?
    @NSManaged var kindRaw: String?
    @NSManaged var date: Date?
    @NSManaged var choreID: UUID?
    @NSManaged var redemptionID: UUID?
    @NSManaged var household: Household?
    @NSManaged var member: Member?

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw ?? "") ?? .chore }
        set { kindRaw = newValue.rawValue }
    }

    /// What this entry pays out for. Entries with the same source are duplicates.
    var sourceKey: String {
        switch kind {
        case .chore: choreID.map { "chore-\($0.uuidString)" } ?? "entry-\(id?.uuidString ?? "")"
        case .redemption: redemptionID.map { "redemption-\($0.uuidString)" } ?? "entry-\(id?.uuidString ?? "")"
        // Every bonus or payout is its own source: two parents each giving one means two.
        case .bonus, .payout: "entry-\(id?.uuidString ?? "")"
        }
    }

    /// One entry per source, keeping the one every device would pick (lowest id).
    static func unique(_ entries: some Sequence<PointEntry>) -> [PointEntry] {
        Dictionary(grouping: entries, by: \.sourceKey).values.compactMap { $0.min(by: syncOrder) }
    }
}

/// A tie-break that every device computes the same way, so duplicate cleanup converges.
func syncOrder<T: NSManagedObject>(_ a: T, _ b: T) -> Bool {
    let ida = (a.value(forKey: "id") as? UUID)?.uuidString ?? ""
    let idb = (b.value(forKey: "id") as? UUID)?.uuidString ?? ""
    return ida < idb
}

/// A one-off push like "Clean house for guests": a set of chores in steps, with a deadline,
/// that can put regular chores on hold until it's done.
@objc(Project)
final class Project: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var emoji: String?
    @NSManaged var dueDate: Date?
    @NSManaged var pausesRegular: Bool
    /// The names of its steps, in order, one per line.
    @NSManaged var phaseNamesRaw: String?
    @NSManaged var createdAt: Date?
    @NSManaged var finishedAt: Date?
    @NSManaged var household: Household?

    var displayTitle: String { title ?? String(localized: "Project") }
    var displayEmoji: String { emoji ?? "📋" }
    var phaseNames: [String] {
        get { (phaseNamesRaw ?? "").split(separator: "\n").map(String.init) }
        set { phaseNamesRaw = newValue.isEmpty ? nil : newValue.joined(separator: "\n") }
    }

    var chores: [Chore] {
        guard let id else { return [] }
        return ((household?.chores as? Set<Chore>) ?? [])
            .filter { $0.projectID == id }
            .sorted { ($0.phase, $0.displayTitle) < ($1.phase, $1.displayTitle) }
    }

    /// Underway: not finished, and its deadline hasn't passed.
    func isActive(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard finishedAt == nil else { return false }
        guard let dueDate else { return true }
        return calendar.startOfDay(for: dueDate) >= calendar.startOfDay(for: now)
    }

    /// Share of its chores that are approved, from 0 to 1.
    var progress: Double {
        let all = chores
        guard !all.isEmpty else { return 0 }
        return Double(all.filter { $0.status == .approved }.count) / Double(all.count)
    }

    func phaseName(_ phase: Int) -> String {
        phaseNames.indices.contains(phase) ? phaseNames[phase] : String(localized: "Step \(phase + 1)")
    }

    /// The first step that still has chores to finish; later steps are best left until it's done.
    var currentPhase: Int? {
        chores.filter { $0.status != .approved }.map { Int($0.phase) }.min()
    }
}
