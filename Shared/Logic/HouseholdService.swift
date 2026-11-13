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

    // MARK: Helpers shared by the extensions

    func addEntry(_ amount: Int32, kind: EntryKind, reason: String, to kid: Member,
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

    func requireParent(_ me: Member) throws {
        guard me.isParent else { throw ServiceError.notAllowed(String(localized: "Only parents can do that.")) }
    }

    func make<T: NSManagedObject>(_ type: T.Type) throws -> T {
        let name = String(describing: type)
        guard let object = NSEntityDescription.insertNewObject(forEntityName: name, into: context) as? T else {
            throw ServiceError.invalid(String(localized: "Couldn't create a \(name). Please try again."))
        }
        return object
    }

    /// New objects must land in the same store as their household, otherwise
    /// something created by an invited person would stay out of the shared database.
    func insert<T: NSManagedObject>(_ type: T.Type, into household: Household) throws -> T {
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
