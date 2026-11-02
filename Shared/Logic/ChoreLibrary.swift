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

        var id: String { "\(age.rawValue)-\(title)" }
    }

    static let templates: [Template] = [
        Template(title: String(localized: "Make your bed"), points: 2, repeats: .daily, age: .little),
        Template(title: String(localized: "Put toys away"), points: 2, repeats: .daily, age: .little),
        Template(title: String(localized: "Clothes in the hamper"), points: 1, repeats: .daily, age: .little),
        Template(title: String(localized: "Feed the pet"), notes: String(localized: "With a grown-up's help."), points: 2, repeats: .daily, age: .little),
        Template(title: String(localized: "Help set the table"), points: 2, repeats: .daily, age: .little),
        Template(title: String(localized: "Water the plants"), points: 2, repeats: .weekly, age: .little),
        Template(title: String(localized: "Bedtime routine"), points: 3, repeats: .daily, age: .little,
                 steps: [String(localized: "Pajamas on"), String(localized: "Brush teeth"), String(localized: "Pick a book")]),
        Template(title: String(localized: "Match the socks"), points: 2, repeats: .weekly, age: .little),

        Template(title: String(localized: "Make your bed"), points: 3, repeats: .daily, age: .kids),
        Template(title: String(localized: "Morning routine"), points: 4, repeats: .daily, age: .kids,
                 steps: [String(localized: "Make your bed"), String(localized: "Get dressed"), String(localized: "Brush teeth"), String(localized: "Pack your school bag")]),
        Template(title: String(localized: "Bedtime routine"), points: 4, repeats: .daily, age: .kids,
                 steps: [String(localized: "Shower or bath"), String(localized: "Pajamas on"), String(localized: "Brush teeth"), String(localized: "Lay out tomorrow's clothes")]),
        Template(title: String(localized: "Pack your school bag"), points: 2, repeats: .daily, age: .kids),
        Template(title: String(localized: "Set the table"), points: 3, repeats: .daily, age: .kids),
        Template(title: String(localized: "Clear the table"), points: 3, repeats: .daily, age: .kids),
        Template(title: String(localized: "Empty the dishwasher"), points: 5, repeats: .daily, age: .kids),
        Template(title: String(localized: "Feed the pet"), points: 3, repeats: .daily, age: .kids),
        Template(title: String(localized: "Tidy your room"), notes: String(localized: "Floor, desk and bed."), points: 5, repeats: .weekly, age: .kids),
        Template(title: String(localized: "Take out the trash"), points: 4, repeats: .weekly, age: .kids),
        Template(title: String(localized: "Fold the laundry"), points: 5, repeats: .weekly, age: .kids),

        Template(title: String(localized: "Load the dishwasher"), points: 5, repeats: .daily, age: .tweens),
        Template(title: String(localized: "Walk the dog"), points: 5, repeats: .daily, age: .tweens),
        Template(title: String(localized: "Trash and recycling out"), points: 5, repeats: .weekly, age: .tweens),
        Template(title: String(localized: "Vacuum the living room"), points: 8, repeats: .weekly, age: .tweens),
        Template(title: String(localized: "Clean the bathroom sink"), notes: String(localized: "Sink, tap and mirror."), points: 8, repeats: .weekly, age: .tweens),
        Template(title: String(localized: "Do your own laundry"), notes: String(localized: "Wash, dry, fold and put away."), points: 10, repeats: .weekly, age: .tweens),
        Template(title: String(localized: "Help cook dinner"), points: 8, repeats: .weekly, age: .tweens),
        Template(title: String(localized: "Mow the lawn"), points: 15, repeats: .none, age: .tweens),
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
