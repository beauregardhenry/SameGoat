import XCTest
@testable import SameGoat

/// Parents can drag the family into any order, and it sticks.
@MainActor
final class MemberOrderTests: ServiceTestCase {
    private var names: [String] { household.memberList.map(\.displayName) }

    func testUntilSomeoneReordersParentsComeFirstThenByName() throws {
        try service.addMember(name: "Ava", role: .kid, emoji: "🐱", to: household, by: parent)
        try service.addMember(name: "Papa", role: .parent, emoji: "🌲", to: household, by: parent)
        XCTAssertEqual(names, ["Mama", "Papa", "Ava", "Sam"])
    }

    func testAParentsOrderIsKept() throws {
        let ava = try service.addMember(name: "Ava", role: .kid, emoji: "🐱", to: household, by: parent)
        try service.reorderMembers([kid, parent, ava], by: parent)
        XCTAssertEqual(names, ["Sam", "Mama", "Ava"])
        XCTAssertEqual(household.kids.map(\.displayName), ["Sam", "Ava"])
    }

    func testSomeoneAddedAfterReorderingGoesLast() throws {
        try service.reorderMembers([kid, parent], by: parent)
        try service.addMember(name: "Ava", role: .kid, emoji: "🐱", to: household, by: parent)
        try service.addMember(name: "Papa", role: .parent, emoji: "🌲", to: household, by: parent)
        XCTAssertEqual(names, ["Sam", "Mama", "Ava", "Papa"])
    }

    func testKidsCannotReorderTheFamily() throws {
        assertThrowsServiceError(try service.reorderMembers([kid, parent], by: kid))
        XCTAssertEqual(names, ["Mama", "Sam"])
    }
}
