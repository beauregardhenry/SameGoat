import XCTest
@testable import SameGoat

@MainActor
final class ProjectTests: ServiceTestCase {
    private var pip: Member!
    private var guests: ProjectLibrary.Preset { ProjectLibrary.presets[0] }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date() }

    override func setUp() async throws {
        try await super.setUp()
        pip = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
    }

    private func start(_ preset: ProjectLibrary.Preset? = nil, kids: [Member] = []) throws -> Project {
        try service.startProject(.init(preset: preset ?? guests, dueDate: tomorrow), sharedWith: kids, in: household, by: parent)
    }

    func testPresetsAreReadyToGo() {
        XCTAssertGreaterThanOrEqual(ProjectLibrary.presets.count, 4)
        for preset in ProjectLibrary.presets {
            XCTAssertFalse(preset.tasks.isEmpty, preset.title)
            XCTAssertTrue(preset.tasks.allSatisfy { preset.phases.indices.contains($0.phase) }, preset.title)
        }
        XCTAssertEqual(guests.title, "Guests are coming")
    }

    func testEveryonePitchesInPutsEveryChoreInThePool() throws {
        let project = try start()
        XCTAssertEqual(project.chores.count, guests.tasks.count)
        XCTAssertTrue(project.chores.allSatisfy { $0.isUnclaimed && $0.dueDate == calendar.startOfDay(for: self.tomorrow) })
        XCTAssertEqual(project.phaseNames, guests.phases)
        XCTAssertEqual(project.chores.first?.phase, 0, "listed in step order")
        XCTAssertTrue(household.activeProjects(calendar: calendar).contains(project))
    }

    func testSharingOutEvensTheTime() throws {
        let project = try start(kids: [kid, pip])
        let minutes = { (kid: Member) in project.chores.filter { $0.assignee == kid }.reduce(0) { $0 + ($1.minutes ?? 0) } }
        XCTAssertTrue(project.chores.allSatisfy { $0.assignee != nil })
        XCTAssertLessThanOrEqual(abs(minutes(kid) - minutes(pip)), 20, "shares within one chore of each other")
    }

    func testRegularChoresWaitWhileAProjectComesFirst() throws {
        let regular = try assign(title: "Dishes", due: calendar.date(byAdding: .day, value: -2, to: Date()))
        XCTAssertTrue(regular.isOverdue(calendar: calendar))
        let project = try start()
        XCTAssertTrue(regular.isOnHold(calendar: calendar))
        XCTAssertFalse(regular.isOverdue(calendar: calendar))
        XCTAssertEqual(household.overridingProject(calendar: calendar), project)
        XCTAssertFalse(project.chores[0].isOnHold(calendar: calendar), "the project's own chores don't wait")

        try service.endProject(project, by: parent)
        XCTAssertTrue(regular.isOverdue(calendar: calendar), "back to normal once it's over")
    }

    func testNoRemindersForChoresOnHold() throws {
        _ = try assign(title: "Dishes", due: calendar.date(byAdding: .day, value: 2, to: Date()))
        _ = try start()
        let titles = Notifier.dueReminders(household: household, me: kid, calendar: calendar).map(\.title)
        XCTAssertFalse(titles.contains("Due today: Dishes"))
    }

    func testSpringCleanRunsAlongsideRegularChores() throws {
        let spring = try XCTUnwrap(ProjectLibrary.presets.first { $0.title == "Spring clean" })
        _ = try start(spring)
        XCTAssertNil(household.overridingProject(calendar: calendar))
    }

    func testFinishingEveryChoreFinishesTheProject() throws {
        let project = try start(kids: [kid])
        XCTAssertEqual(project.currentPhase, 0)
        for chore in project.chores {
            try service.markComplete(chore, by: kid, note: nil, photo: nil)
            try service.approve(chore, by: parent)
        }
        XCTAssertNotNil(project.finishedAt)
        XCTAssertEqual(project.progress, 1)
        XCTAssertNil(project.currentPhase)
        XCTAssertFalse(project.isActive(calendar: calendar))
    }

    func testProgressAndCurrentStep() throws {
        let project = try start(kids: [kid])
        for chore in project.chores where chore.phase == 0 {
            try service.markComplete(chore, by: kid, note: nil, photo: nil)
            try service.approve(chore, by: parent)
        }
        XCTAssertEqual(project.currentPhase, 1)
        XCTAssertEqual(project.progress, 3.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(project.phaseName(1), "Clean")
        XCTAssertEqual(project.phaseName(9), "Step 10")
    }

    func testEndingKeepsEarnedPointsAndDropsTheRest() throws {
        let project = try start(kids: [kid])
        let first = project.chores[0]
        try service.markComplete(first, by: kid, note: nil, photo: nil)
        try service.approve(first, by: parent)
        let earned = kid.balance
        try service.endProject(project, by: parent)
        XCTAssertEqual(project.chores.count, 1)
        XCTAssertEqual(kid.balance, earned)
        XCTAssertNotNil(project.finishedAt)
    }

    func testAPassedDeadlineEndsTheHold() throws {
        let project = try start()
        project.dueDate = calendar.date(byAdding: .day, value: -1, to: Date())
        XCTAssertFalse(project.isActive(calendar: calendar))
        XCTAssertNil(household.overridingProject(calendar: calendar))
    }

    func testProjectRules() throws {
        var blank = HouseholdService.ProjectDraft()
        blank.title = "Empty"
        assertThrowsServiceError(try service.startProject(blank, sharedWith: [], in: household, by: parent))
        var unnamed = HouseholdService.ProjectDraft(preset: guests, dueDate: tomorrow)
        unnamed.title = " "
        assertThrowsServiceError(try service.startProject(unnamed, sharedWith: [], in: household, by: parent))
        let past = HouseholdService.ProjectDraft(preset: guests, dueDate: calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date())
        assertThrowsServiceError(try service.startProject(past, sharedWith: [], in: household, by: parent))
        assertThrowsServiceError(try service.startProject(.init(preset: guests, dueDate: tomorrow), sharedWith: [], in: household, by: kid))
        assertThrowsServiceError(try service.startProject(.init(preset: guests, dueDate: tomorrow), sharedWith: [parent], in: household, by: parent))
        let project = try start()
        assertThrowsServiceError(try service.endProject(project, by: kid))
        XCTAssertEqual(project.displayEmoji, "🏡")
    }
}
