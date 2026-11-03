import XCTest
@testable import HappyMama

@MainActor
final class FamilyMoodTests: ServiceTestCase {
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ n: Int) -> Date { (calendar.date(byAdding: .day, value: n, to: today) ?? today).addingTimeInterval(12 * 3600) }

    func testOneCheckInPerPersonPerDayAndItCanChange() throws {
        try service.checkInMood(2, note: " tired ", by: kid)
        try service.checkInMood(4, by: kid)
        let mine = try XCTUnwrap(FamilyMood.checkIn(by: kid, on: Date(), calendar: calendar))
        XCTAssertEqual(mine.rating, 4)
        XCTAssertNil(mine.note)
        XCTAssertEqual(FamilyMood.checkIns(in: household).count, 1)
        assertThrowsServiceError(try service.checkInMood(0, by: kid))
        assertThrowsServiceError(try service.checkInMood(6, by: kid))
    }

    func testFamilyAverageAndTrend() throws {
        try service.checkInMood(2, by: kid, now: day(-1))
        try service.checkInMood(4, by: parent, now: day(-1))
        try service.checkInMood(5, by: kid, now: day(0))
        XCTAssertEqual(FamilyMood.average(on: day(-1), in: household, calendar: calendar), 3)
        let trend = FamilyMood.trend(days: 3, in: household, calendar: calendar)
        XCTAssertEqual(trend.map(\.average), [3, 5])
        XCTAssertEqual(FamilyMood.average(for: kid, days: 7, calendar: calendar), 3.5)
        XCTAssertNil(FamilyMood.average(for: parent, days: 1, calendar: calendar))
        XCTAssertEqual(FamilyMood.face(5), "😄")
    }

    func testSyncDuplicatesKeepTheLatest() throws {
        let first = try service.checkInMood(2, by: kid)
        // The same check-in, saved on another device a moment later.
        let copy = MoodCheckIn(context: service.context)
        copy.id = UUID()
        copy.day = first.day
        copy.rating = 5
        copy.createdAt = Date().addingTimeInterval(60)
        copy.member = kid
        copy.household = household
        XCTAssertEqual(FamilyMood.checkIn(by: kid, on: Date(), calendar: calendar)?.rating, 5)
        try service.resolveSyncDuplicates(in: household)
        XCTAssertEqual((household.moods as? Set<MoodCheckIn>)?.count, 1)
    }

    func testRemovingSomeoneRemovesTheirCheckIns() throws {
        try service.checkInMood(3, by: kid)
        try service.removeMember(kid, by: parent)
        XCTAssertEqual((household.moods as? Set<MoodCheckIn>)?.count ?? 0, 0)
    }

    /// Weeks where `parent` does "Go to the gym" three times get happier check-ins.
    private func seedGymWeeks() throws {
        let thisWeek = WeeklyRecap.weekStart(for: Date(), calendar: calendar)
        for weeksAgo in 1...6 {
            let gymWeek = weeksAgo % 2 == 0
            let start = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek))
            for offset in 0..<7 {
                let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start)).addingTimeInterval(12 * 3600)
                try service.checkInMood(gymWeek ? 4 : 3, by: kid, now: date)
                if gymWeek && offset < 3 {
                    var draft = HouseholdService.ChoreDraft()
                    draft.title = "Go to the gym"
                    draft.dueDate = date
                    let gym = try service.createChores(draft, assignees: [parent], in: household, by: parent)[0]
                    try service.markComplete(gym, by: parent, note: nil, photo: nil)
                    gym.completedAt = date
                }
            }
        }
    }

    func testNoticesAHabitThatGoesWithHappierWeeks() throws {
        try seedGymWeeks()
        let insights = MoodInsights.insights(for: household, calendar: calendar)
        let gym = try XCTUnwrap(insights.first { $0.text.contains("Go to the gym") })
        XCTAssertTrue(gym.text.hasPrefix("On weeks Mama did"))
        XCTAssertEqual(gym.strength, 1, accuracy: 0.01)
        XCTAssertEqual(insights.filter { $0.text.contains("Go to the gym") }.count, 1, "said once, not twice")
    }

    func testSaysNothingWithoutEnoughData() throws {
        try service.checkInMood(5, by: kid, now: day(-1))
        var draft = HouseholdService.ChoreDraft()
        draft.title = "Go to the gym"
        draft.dueDate = day(-1)
        let gym = try service.createChores(draft, assignees: [parent], in: household, by: parent)[0]
        try service.markComplete(gym, by: parent, note: nil, photo: nil)
        XCTAssertTrue(MoodInsights.insights(for: household, calendar: calendar).isEmpty)
    }

    func testNoticesOccasionalThingsByDay() throws {
        for back in 1...20 {
            let good = back % 5 == 0
            try service.checkInMood(good ? 5 : 3, by: kid, now: day(-back))
            if good {
                var draft = HouseholdService.ChoreDraft()
                draft.title = "Family game night"
                draft.dueDate = day(-back)
                let night = try service.createChores(draft, assignees: [parent], in: household, by: parent)[0]
                try service.markComplete(night, by: parent, note: nil, photo: nil)
                night.completedAt = day(-back)
            }
        }
        let insight = try XCTUnwrap(MoodInsights.insights(for: household, calendar: calendar).first)
        XCTAssertTrue(insight.text.hasPrefix("Days with “Family game night” averaged 5.0"))
    }

    func testBoostersThatWorkedBeforeComeFirst() throws {
        XCTAssertEqual(MoodInsights.suggestedBoosters(for: household, calendar: calendar).count, 4)
        try service.checkInMood(5, by: kid, now: day(-2))
        let picnic = try XCTUnwrap(MoodInsights.boosters.first { $0.title == "Picnic" })
        let planned = try service.planBooster(picnic, by: parent, now: day(-2))
        XCTAssertEqual(planned.assignee, parent)
        XCTAssertTrue(planned.isFamilyJob)
        try service.markComplete(planned, by: parent, note: nil, photo: nil)
        planned.completedAt = day(-2)
        let first = try XCTUnwrap(MoodInsights.suggestedBoosters(for: household, calendar: calendar).first)
        XCTAssertEqual(first.booster.title, "Picnic")
        XCTAssertEqual(first.before, 5)
        assertThrowsServiceError(try service.planBooster(picnic, by: kid))
    }

    func testRoughWeeksSuggestGentleIdeas() throws {
        for back in 0..<5 { try service.checkInMood(2, by: kid, now: day(-back)) }
        let ideas = MoodInsights.suggestedBoosters(for: household, calendar: calendar)
        XCTAssertTrue(ideas.allSatisfy(\.booster.lowEnergy))
    }

    func testFlagsALowKidWithTheMostToDo() throws {
        let pip = try service.addMember(name: "Pip", role: .kid, emoji: "🐸", to: household, by: parent)
        for back in 0..<4 { try service.checkInMood(2, by: kid, now: day(-back)) }
        var big = HouseholdService.ChoreDraft()
        big.title = "Garage"
        big.minutes = 60
        try service.createChores(big, assignees: [kid], in: household, by: parent)
        var small = HouseholdService.ChoreDraft()
        small.title = "Socks"
        small.minutes = 5
        try service.createChores(small, assignees: [pip], in: household, by: parent)

        let notes = MoodInsights.workloadNotes(for: household, calendar: calendar)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].hasPrefix("Sam's mood has been low this week"))
    }
}
