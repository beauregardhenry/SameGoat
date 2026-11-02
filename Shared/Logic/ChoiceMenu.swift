import Foundation

/// "Pick 2 of these 5 this week": a set of chores a kid chooses from. Choosing is motivating
/// in itself, and it shows whether a kid always goes for the easy ones.
enum ChoiceMenu {
    /// The options in the same menu as `chore`, picked or not, still to do or done.
    static func options(like chore: Chore) -> [Chore] {
        guard let id = chore.menuID else { return [] }
        return ((chore.household?.chores as? Set<Chore>) ?? [])
            .filter { $0.menuID == id }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    static func pickedCount(like chore: Chore) -> Int {
        options(like: chore).filter(\.menuPicked).count
    }

    /// True when a kid's last three picks were all the easiest option left.
    static func prefersEasy(_ kid: Member) -> Bool {
        let picks = ((kid.assignedChores as? Set<Chore>) ?? [])
            .filter { $0.menuID != nil && $0.menuPicked }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(3)
        return picks.count == 3 && picks.allSatisfy(\.menuEasiest)
    }

    static func rank(_ difficulty: Difficulty?) -> Int {
        switch difficulty {
        case .easy: 1
        case .medium, nil: 2
        case .hard: 3
        }
    }
}

extension HouseholdService {
    /// Gives each kid their own menu of `templates` to choose `pick` from, due by the end of the week.
    @discardableResult
    func addChoiceMenu(_ templates: [ChoreLibrary.Template], pick: Int, for kids: [Member],
                       in household: Household, by me: Member) throws -> [Chore] {
        guard me.isParent else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
        guard templates.count >= 2 else { throw ServiceError.invalid(String(localized: "Pick at least two chores to choose from.")) }
        guard (1..<templates.count).contains(pick) else {
            throw ServiceError.invalid(String(localized: "Let them choose fewer than all of them."))
        }
        guard !kids.isEmpty, kids.allSatisfy({ !$0.isParent }) else {
            throw ServiceError.invalid(String(localized: "Choose which kids get the menu."))
        }
        var created: [Chore] = []
        for kid in kids {
            let menu = UUID()
            for template in templates {
                var draft = ChoreLibrary.draft(from: template)
                draft.recurrence = RecurrenceRule()
                draft.takeTurns = false
                draft.dueDate = Date()
                draft.dueWithinWeek = true
                let chore = try createChores(draft, assignees: [kid], in: household, by: me, saving: false)[0]
                chore.menuID = menu
                chore.menuPick = Int16(pick)
                created.append(chore)
            }
        }
        try save()
        return created
    }

    /// A kid chooses one option. Once they've chosen enough, the rest of their menu goes away.
    func pick(_ chore: Chore, by me: Member) throws {
        guard !me.isParent, chore.assignee?.id == me.id, chore.status == .todo else {
            throw ServiceError.notAllowed(String(localized: "This isn't your chore."))
        }
        guard chore.isMenuOption else { throw ServiceError.invalid(String(localized: "This one is already picked.")) }
        let options = ChoiceMenu.options(like: chore)
        let remaining = options.filter(\.isMenuOption)
        chore.menuEasiest = ChoiceMenu.rank(chore.difficulty) <= remaining.map { ChoiceMenu.rank($0.difficulty) }.min() ?? 1
        chore.menuPicked = true
        if options.filter(\.menuPicked).count >= Int(chore.menuPick) {
            remaining.filter { $0 !== chore }.forEach(context.delete)
        }
        try save()
    }

    /// Changes a kid's mind about an option, while there's still a choice to make.
    func unpick(_ chore: Chore, by me: Member) throws {
        guard !me.isParent, chore.assignee?.id == me.id, chore.status == .todo, chore.menuPicked,
              ChoiceMenu.options(like: chore).contains(where: \.isMenuOption) else {
            throw ServiceError.invalid(String(localized: "You can't change this choice anymore."))
        }
        chore.menuPicked = false
        chore.menuEasiest = false
        try save()
    }
}
