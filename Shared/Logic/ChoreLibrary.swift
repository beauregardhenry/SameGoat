import Foundation

/// Ready-made chores grouped by age, so setting up a family takes seconds.
enum ChoreLibrary {
    enum Age: String, CaseIterable, Identifiable {
        case little, kids, tweens
        var id: String { rawValue }
        var title: String {
            switch self {
            case .little: String(localized: "Little ones (3–5)")
            case .kids: String(localized: "Kids (6–9)")
            case .tweens: String(localized: "Tweens (10+)")
            }
        }
    }

    struct Template: Identifiable, Equatable {
        let title: String
        var notes = ""
        let points: Int
        let repeats: Recurrence
        let age: Age
        /// Set for a routine: the checklist the kid ticks through.
        var steps: [String] = []
        /// About how long it takes and how hard it is.
        var minutes: Int?
        var difficulty: Difficulty?
        var emoji: String?
        var timeOfDay: TimeOfDay?
        /// How it helps the family, and a tip for doing it well.
        var helps: String?
        var tips: String?

        var id: String { "\(age.rawValue)-\(title)" }
    }

    static let templates: [Template] = [
        Template(title: String(localized: "Make your bed"), points: 2, repeats: .daily, age: .little, minutes: 5, difficulty: .easy, emoji: "🛏️", timeOfDay: .morning,
                 helps: String(localized: "A made bed makes the whole room feel calm."), tips: String(localized: "Pull the covers up first, then fluff the pillow.")),
        Template(title: String(localized: "Put toys away"), points: 2, repeats: .daily, age: .little, minutes: 10, difficulty: .easy, emoji: "🧸", timeOfDay: .evening,
                 helps: String(localized: "Clear floors mean nobody trips and toys don't get lost."), tips: String(localized: "Pick one kind of toy at a time: cars first, then blocks.")),
        Template(title: String(localized: "Clothes in the hamper"), points: 1, repeats: .daily, age: .little, minutes: 5, difficulty: .easy, emoji: "🧺", timeOfDay: .evening,
                 helps: String(localized: "Laundry can only get clean if it reaches the hamper."), tips: String(localized: "Do it right when you change, so it's never a pile.")),
        Template(title: String(localized: "Feed the pet"), notes: String(localized: "With a grown-up's help."), points: 2, repeats: .daily, age: .little, minutes: 5, difficulty: .easy, emoji: "🐶", timeOfDay: .morning,
                 helps: String(localized: "Our pet counts on us every single day."), tips: String(localized: "Check the water bowl too.")),
        Template(title: String(localized: "Help set the table"), points: 2, repeats: .daily, age: .little, minutes: 5, difficulty: .easy, emoji: "🍽️", timeOfDay: .evening,
                 helps: String(localized: "Dinner is ready faster when everyone helps."), tips: String(localized: "Count the people first, then grab that many of everything.")),
        Template(title: String(localized: "Water the plants"), points: 2, repeats: .weekly, age: .little, minutes: 10, difficulty: .easy, emoji: "🪴",
                 helps: String(localized: "Plants make our home nicer, and they need us to stay alive."), tips: String(localized: "Water until it just starts to come out the bottom.")),
        Template(title: String(localized: "Bedtime routine"), points: 3, repeats: .daily, age: .little,
                 steps: [String(localized: "Pajamas on"), String(localized: "Brush teeth"), String(localized: "Pick a book")], minutes: 15, difficulty: .easy, emoji: "🌙", timeOfDay: .evening,
                 helps: String(localized: "A smooth bedtime means more time for stories."), tips: String(localized: "Do it in the same order every night.")),
        Template(title: String(localized: "Match the socks"), points: 2, repeats: .weekly, age: .little, minutes: 10, difficulty: .medium, emoji: "🧦",
                 helps: String(localized: "Matched socks mean faster mornings for everyone."), tips: String(localized: "Lay them all out first, then find pairs.")),

        Template(title: String(localized: "Make your bed"), points: 3, repeats: .daily, age: .kids, minutes: 5, difficulty: .easy, emoji: "🛏️", timeOfDay: .morning,
                 helps: String(localized: "A made bed makes the whole room feel calm."), tips: String(localized: "Pull the covers up first, then fluff the pillow.")),
        Template(title: String(localized: "Morning routine"), points: 4, repeats: .daily, age: .kids,
                 steps: [String(localized: "Make your bed"), String(localized: "Get dressed"), String(localized: "Brush teeth"), String(localized: "Pack your school bag")], minutes: 20, difficulty: .easy, emoji: "☀️", timeOfDay: .morning,
                 helps: String(localized: "When everyone's ready on time, mornings are calm for the whole family."), tips: String(localized: "Lay out your clothes the night before.")),
        Template(title: String(localized: "Bedtime routine"), points: 4, repeats: .daily, age: .kids,
                 steps: [String(localized: "Shower or bath"), String(localized: "Pajamas on"), String(localized: "Brush teeth"), String(localized: "Lay out tomorrow's clothes")], minutes: 20, difficulty: .easy, emoji: "🌙", timeOfDay: .evening,
                 helps: String(localized: "A smooth bedtime means more time for stories."), tips: String(localized: "Do it in the same order every night.")),
        Template(title: String(localized: "Pack your school bag"), points: 2, repeats: .daily, age: .kids, minutes: 5, difficulty: .easy, emoji: "🎒", timeOfDay: .evening,
                 helps: String(localized: "No last-minute searching means a calmer morning for everyone."), tips: String(localized: "Check tomorrow's schedule before you pack.")),
        Template(title: String(localized: "Set the table"), points: 3, repeats: .daily, age: .kids, minutes: 5, difficulty: .easy, emoji: "🍽️", timeOfDay: .evening,
                 helps: String(localized: "Dinner is ready faster when everyone helps."), tips: String(localized: "Plates first, then cutlery, then cups.")),
        Template(title: String(localized: "Clear the table"), points: 3, repeats: .daily, age: .kids, minutes: 10, difficulty: .easy, emoji: "🍽️", timeOfDay: .evening,
                 helps: String(localized: "A clear table means dishes get done and we can relax sooner."), tips: String(localized: "Stack plates with the scraps on top.")),
        Template(title: String(localized: "Empty the dishwasher"), points: 5, repeats: .daily, age: .kids, minutes: 10, difficulty: .medium, emoji: "🧽", timeOfDay: .afternoon,
                 helps: String(localized: "Empty dishwasher, empty sink: dirty dishes have somewhere to go."), tips: String(localized: "Do the cutlery basket first; it's the fastest.")),
        Template(title: String(localized: "Feed the pet"), points: 3, repeats: .daily, age: .kids, minutes: 5, difficulty: .easy, emoji: "🐶", timeOfDay: .morning,
                 helps: String(localized: "Our pet counts on us every single day."), tips: String(localized: "Check the water bowl too.")),
        Template(title: String(localized: "Tidy your room"), notes: String(localized: "Floor, desk and bed."), points: 5, repeats: .weekly, age: .kids, minutes: 20, difficulty: .medium, emoji: "🧹",
                 helps: String(localized: "A tidy room is yours to enjoy, and easier to clean."), tips: String(localized: "Start with the floor, then the desk, then the bed.")),
        Template(title: String(localized: "Take out the trash"), points: 4, repeats: .weekly, age: .kids, minutes: 10, difficulty: .easy, emoji: "🗑️", timeOfDay: .evening,
                 helps: String(localized: "Nobody likes a smelly kitchen. This keeps it fresh for all of us."), tips: String(localized: "Put a new bag in right away.")),
        Template(title: String(localized: "Fold the laundry"), points: 5, repeats: .weekly, age: .kids, minutes: 15, difficulty: .medium, emoji: "👕",
                 helps: String(localized: "Folded clothes mean everyone can find what they need."), tips: String(localized: "Fold while it's still warm from the dryer: fewer wrinkles.")),

        Template(title: String(localized: "Load the dishwasher"), points: 5, repeats: .daily, age: .tweens, minutes: 10, difficulty: .medium, emoji: "🧽", timeOfDay: .evening,
                 helps: String(localized: "Clean dishes for the next meal, for the whole family."), tips: String(localized: "Big things at the back, nothing blocking the spinner.")),
        Template(title: String(localized: "Walk the dog"), points: 5, repeats: .daily, age: .tweens, minutes: 20, difficulty: .easy, emoji: "🐕", timeOfDay: .afternoon,
                 helps: String(localized: "Walks keep our dog happy, healthy and calm at home."), tips: String(localized: "Bring a bag and check the weather.")),
        Template(title: String(localized: "Trash and recycling out"), points: 5, repeats: .weekly, age: .tweens, minutes: 10, difficulty: .easy, emoji: "♻️", timeOfDay: .evening,
                 helps: String(localized: "Trash day only comes once a week; this keeps the house fresh."), tips: String(localized: "Sort as you go: paper, plastic, glass.")),
        Template(title: String(localized: "Vacuum the living room"), points: 8, repeats: .weekly, age: .tweens, minutes: 20, difficulty: .medium, emoji: "🧹",
                 helps: String(localized: "A clean living room is where we all hang out."), tips: String(localized: "Pick things up off the floor first.")),
        Template(title: String(localized: "Clean the bathroom sink"), notes: String(localized: "Sink, tap and mirror."), points: 8, repeats: .weekly, age: .tweens, minutes: 15, difficulty: .hard, emoji: "🚿",
                 helps: String(localized: "A clean bathroom is healthier for everyone."), tips: String(localized: "Spray, wait a minute, then wipe; it does the work for you.")),
        Template(title: String(localized: "Do your own laundry"), notes: String(localized: "Wash, dry, fold and put away."), points: 10, repeats: .weekly, age: .tweens, minutes: 30, difficulty: .medium, emoji: "🧺",
                 helps: String(localized: "Taking care of your own clothes is a big step toward independence."), tips: String(localized: "Sort lights and darks, and empty your pockets first.")),
        Template(title: String(localized: "Help cook dinner"), points: 8, repeats: .weekly, age: .tweens, minutes: 30, difficulty: .medium, emoji: "🍳", timeOfDay: .evening,
                 helps: String(localized: "Cooking together means dinner sooner, and you learn a life skill."), tips: String(localized: "Read the whole recipe before you start.")),
        Template(title: String(localized: "Mow the lawn"), points: 15, repeats: .none, age: .tweens, minutes: 60, difficulty: .hard, emoji: "🌱",
                 helps: String(localized: "A mowed lawn is safer to play on and looks great."), tips: String(localized: "Mow in straight lines, overlapping a little each time.")),
    ]

    static func templates(for age: Age) -> [Template] {
        templates.filter { $0.age == age }
    }

    /// A chore draft for the template. Repeating chores start today, since they need a date to repeat from.
    static func draft(from template: Template, today: Date = Date(), takeTurns: Bool = false) -> HouseholdService.ChoreDraft {
        var draft = HouseholdService.ChoreDraft()
        draft.title = template.title
        draft.notes = template.notes
        draft.points = template.points
        draft.recurrence.kind = template.repeats
        draft.dueDate = template.repeats == .none ? nil : today
        draft.takeTurns = takeTurns && template.repeats != .none
        draft.steps = template.steps
        draft.minutes = template.minutes
        draft.difficulty = template.difficulty
        draft.emoji = template.emoji
        draft.timeOfDay = template.timeOfDay
        draft.whyItHelps = template.helps ?? ""
        draft.tips = template.tips ?? ""
        return draft
    }
}

extension HouseholdService {
    /// Adds several library chores at once. Each kid gets a copy, or with `takeTurns`
    /// the kids take turns on the repeating ones.
    @discardableResult
    func addFromLibrary(_ templates: [ChoreLibrary.Template], assignees: [Member], takeTurns: Bool,
                        in household: Household, by me: Member) throws -> [Chore] {
        guard !templates.isEmpty else { throw ServiceError.invalid(String(localized: "Pick at least one chore.")) }
        let turns = takeTurns && assignees.count > 1
        return try templates.flatMap { template in
            try createChores(ChoreLibrary.draft(from: template, takeTurns: turns), assignees: assignees, in: household, by: me)
        }
    }
}
