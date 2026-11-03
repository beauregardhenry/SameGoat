import XCTest
@testable import SameGoat

@MainActor
final class FeatureTests: ServiceTestCase {
    func testANewFamilyStartsWithTheBasics() {
        XCTAssertTrue(household.features.isEmpty)
        XCTAssertFalse(household.has(.mood))
    }

    func testFamiliesCanPickExtrasWhenTheyStart() throws {
        let other = try service.createHousehold(name: "Other", yourName: "Dad", emoji: "🌻", userID: "u-2",
                                                features: [.mood, .board])
        XCTAssertEqual(other.features, [.mood, .board])
        XCTAssertEqual(other.featuresRaw, "board,mood")
    }

    func testParentsSwitchFeaturesOnAndOff() throws {
        try service.setFeature(.choiceMenus, on: true, for: household, by: parent)
        XCTAssertTrue(household.has(.choiceMenus))
        try service.setFeature(.choiceMenus, on: false, for: household, by: parent)
        XCTAssertFalse(household.has(.choiceMenus))
        assertThrowsServiceError(try service.setFeature(.mood, on: true, for: household, by: kid))
        household.featuresRaw = "mood,not-a-feature"
        XCTAssertEqual(household.features, [.mood], "unknown names are ignored")
    }

    func testTurningProjectsOffLiftsTheirHold() throws {
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let regular = try assign(title: "Dishes", due: calendar.date(byAdding: .day, value: -2, to: Date()))
        _ = try service.startProject(.init(preset: ProjectLibrary.presets[0], dueDate: tomorrow), sharedWith: [],
                                     in: household, by: parent)
        XCTAssertTrue(household.has(.projects), "starting a project turns projects on")
        XCTAssertTrue(regular.isOnHold(calendar: calendar))

        try service.setFeature(.projects, on: false, for: household, by: parent)
        XCTAssertTrue(household.activeProjects(calendar: calendar).isEmpty)
        XCTAssertFalse(regular.isOnHold(calendar: calendar))
        XCTAssertTrue(regular.isOverdue(calendar: calendar))
    }

    func testEveryFeatureExplainsItself() {
        for feature in Feature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.detail.isEmpty)
            XCTAssertFalse(feature.icon.isEmpty)
        }
    }
}
