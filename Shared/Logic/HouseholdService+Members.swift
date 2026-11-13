import CoreData

// Household and member rules: who is in the family, what they may do, and signing in.
extension HouseholdService {
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
}
