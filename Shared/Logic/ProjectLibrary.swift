import CoreData

/// The big one-off pushes every family does, ready to start in a tap.
enum ProjectLibrary {
    struct Task: Identifiable, Equatable {
        let title: String
        let emoji: String
        let minutes: Int
        let difficulty: Difficulty
        let points: Int
        /// Which step it belongs to, from 0.
        let phase: Int
        var id: String { "\(phase)-\(title)" }
    }

    struct Preset: Identifiable, Equatable {
        let title: String
        let emoji: String
        let phases: [String]
        let tasks: [Task]
        /// Most projects come first; a slow one like spring cleaning sits alongside the usual chores.
        var pausesRegular = true
        var id: String { title }
    }

    static let presets: [Preset] = [
        Preset(title: String(localized: "Guests are coming"), emoji: "🏡",
               phases: [String(localized: "Tidy up"), String(localized: "Clean"), String(localized: "Finishing touches")],
               tasks: [
                   Task(title: String(localized: "Put away shoes and coats"), emoji: "👟", minutes: 10, difficulty: .easy, points: 3, phase: 0),
                   Task(title: String(localized: "Clear the counters"), emoji: "🍽️", minutes: 10, difficulty: .easy, points: 3, phase: 0),
                   Task(title: String(localized: "Tidy the living room"), emoji: "🛋️", minutes: 15, difficulty: .easy, points: 4, phase: 0),
                   Task(title: String(localized: "Clean the bathroom"), emoji: "🚽", minutes: 20, difficulty: .medium, points: 8, phase: 1),
                   Task(title: String(localized: "Wipe down the kitchen"), emoji: "🧽", minutes: 15, difficulty: .medium, points: 5, phase: 1),
                   Task(title: String(localized: "Dust the shelves"), emoji: "🪶", minutes: 10, difficulty: .easy, points: 3, phase: 1),
                   Task(title: String(localized: "Vacuum the floors"), emoji: "🧹", minutes: 20, difficulty: .medium, points: 6, phase: 2),
                   Task(title: String(localized: "Put out fresh towels"), emoji: "🧺", minutes: 5, difficulty: .easy, points: 2, phase: 2),
                   Task(title: String(localized: "Take out the trash"), emoji: "🗑️", minutes: 5, difficulty: .easy, points: 2, phase: 2),
               ]),
        Preset(title: String(localized: "Clean the garage"), emoji: "🚗",
               phases: [String(localized: "Sort"), String(localized: "Clean"), String(localized: "Put back")],
               tasks: [
                   Task(title: String(localized: "Sort what stays and what goes"), emoji: "📦", minutes: 30, difficulty: .medium, points: 9, phase: 0),
                   Task(title: String(localized: "Bag up things to donate"), emoji: "🛍️", minutes: 20, difficulty: .easy, points: 5, phase: 0),
                   Task(title: String(localized: "Sweep the floor"), emoji: "🧹", minutes: 20, difficulty: .medium, points: 6, phase: 1),
                   Task(title: String(localized: "Wipe the shelves"), emoji: "🧽", minutes: 15, difficulty: .easy, points: 4, phase: 1),
                   Task(title: String(localized: "Put the tools back"), emoji: "🔧", minutes: 20, difficulty: .medium, points: 6, phase: 2),
                   Task(title: String(localized: "Load donations into the car"), emoji: "🚙", minutes: 10, difficulty: .easy, points: 3, phase: 2),
               ]),
        Preset(title: String(localized: "Yard cleanup"), emoji: "🍂",
               phases: [String(localized: "Pick up"), String(localized: "Clean up"), String(localized: "Finish")],
               tasks: [
                   Task(title: String(localized: "Pick up toys and sticks"), emoji: "🪵", minutes: 15, difficulty: .easy, points: 4, phase: 0),
                   Task(title: String(localized: "Rake the leaves"), emoji: "🍂", minutes: 30, difficulty: .hard, points: 12, phase: 1),
                   Task(title: String(localized: "Pull weeds"), emoji: "🌿", minutes: 30, difficulty: .medium, points: 9, phase: 1),
                   Task(title: String(localized: "Sweep the path"), emoji: "🧹", minutes: 15, difficulty: .easy, points: 4, phase: 2),
                   Task(title: String(localized: "Water the plants"), emoji: "🪴", minutes: 10, difficulty: .easy, points: 3, phase: 2),
               ]),
        Preset(title: String(localized: "Spring clean"), emoji: "🌸",
               phases: [String(localized: "Declutter"), String(localized: "Deep clean"), String(localized: "Refresh")],
               tasks: [
                   Task(title: String(localized: "Clear out your closet"), emoji: "👕", minutes: 30, difficulty: .medium, points: 9, phase: 0),
                   Task(title: String(localized: "Donate toys you've outgrown"), emoji: "🧸", minutes: 20, difficulty: .easy, points: 5, phase: 0),
                   Task(title: String(localized: "Wash the windows"), emoji: "🪟", minutes: 30, difficulty: .medium, points: 9, phase: 1),
                   Task(title: String(localized: "Wipe the baseboards"), emoji: "🧽", minutes: 20, difficulty: .medium, points: 6, phase: 1),
                   Task(title: String(localized: "Wash the bedding"), emoji: "🛏️", minutes: 15, difficulty: .easy, points: 4, phase: 2),
                   Task(title: String(localized: "Vacuum under the furniture"), emoji: "🧹", minutes: 20, difficulty: .medium, points: 6, phase: 2),
               ],
               pausesRegular: false),
    ]
}

extension HouseholdService {
    struct ProjectDraft {
        var title = ""
        var emoji = "📋"
        var dueDate = Date()
        var pausesRegular = true
        var phases: [String] = []
        var tasks: [ProjectLibrary.Task] = []

        init() {}

        init(preset: ProjectLibrary.Preset, dueDate: Date) {
            title = preset.title
            emoji = preset.emoji
            self.dueDate = dueDate
            pausesRegular = preset.pausesRegular
            phases = preset.phases
            tasks = preset.tasks
        }
    }

    /// Starts a project: one chore per task, due by the deadline. With no kids chosen every task is
    /// up for grabs ("everyone pitches in"); otherwise tasks are shared out, each to whoever has the
    /// fewest minutes so far, so the work comes out even.
    @discardableResult
    func startProject(_ draft: ProjectDraft, sharedWith kids: [Member], in household: Household, by me: Member) throws -> Project {
        guard me.isParent else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
        let title = draft.title.trimmed
        guard !title.isEmpty else { throw ServiceError.invalid(String(localized: "Give the project a name.")) }
        guard !draft.tasks.isEmpty else { throw ServiceError.invalid(String(localized: "Add at least one chore to the project.")) }
        guard calendar.startOfDay(for: draft.dueDate) >= calendar.startOfDay(for: Date()) else {
            throw ServiceError.invalid(String(localized: "Pick a deadline that hasn't passed yet."))
        }
        guard kids.allSatisfy({ !$0.isParent }) else { throw ServiceError.invalid(String(localized: "Chores can only be assigned to kids.")) }

        guard let project = NSEntityDescription.insertNewObject(forEntityName: "Project", into: context) as? Project else {
            throw ServiceError.invalid(String(localized: "Couldn't create a \("Project"). Please try again."))
        }
        if let store = household.objectID.persistentStore { context.assign(project, to: store) }
        project.id = UUID()
        project.title = title
        project.emoji = draft.emoji
        project.dueDate = calendar.startOfDay(for: draft.dueDate)
        project.pausesRegular = draft.pausesRegular
        project.phaseNames = draft.phases
        project.createdAt = Date()
        project.household = household
        household.features.insert(.projects)

        var load = Dictionary(uniqueKeysWithValues: kids.map { ($0.objectID, 0) })
        // Biggest jobs first, so the shares even out.
        for task in draft.tasks.sorted(by: { $0.minutes > $1.minutes }) {
            var chore = ChoreDraft()
            chore.title = task.title
            chore.emoji = task.emoji
            chore.minutes = task.minutes
            chore.difficulty = task.difficulty
            chore.points = task.points
            chore.dueDate = draft.dueDate
            chore.upForGrabs = kids.isEmpty
            let kid = kids.min { (load[$0.objectID] ?? 0, $0.displayName) < (load[$1.objectID] ?? 0, $1.displayName) }
            if let kid { load[kid.objectID, default: 0] += task.minutes }
            let created = try createChores(chore, assignees: kid.map { [$0] } ?? [], in: household, by: me, saving: false)
            created.forEach {
                $0.projectID = project.id
                $0.phase = Int16(task.phase)
            }
        }
        try save()
        return project
    }

    /// Calls a project off: its unfinished chores go, finished ones (and their points) stay.
    func endProject(_ project: Project, by me: Member) throws {
        guard me.isParent else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
        for chore in project.chores where chore.status != .approved {
            context.delete(chore)
        }
        project.finishedAt = Date()
        try save()
    }

    /// Marks a project finished once every one of its chores is approved.
    func finishProjectIfDone(for chore: Chore) {
        guard let project = chore.project, project.finishedAt == nil,
              project.chores.allSatisfy({ $0.status == .approved }) else { return }
        project.finishedAt = Date()
    }
}
