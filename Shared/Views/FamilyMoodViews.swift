import SwiftUI
import Charts

/// "How's the family feeling today?" One tap a day, shown at the top of the chore list.
struct MoodCheckInCard: View {
    @ObservedObject var me: Member
    /// Off on the Family Mood screen itself, where pointing to it would be silly.
    var showsWhereToLook = true
    @EnvironmentObject private var service: HouseholdService
    @State private var error: String?

    var body: some View {
        let today = FamilyMood.checkIn(by: me, on: Date())
        VStack(alignment: .leading, spacing: 10) {
            Text(today == nil ? "How's the family feeling today?" : "Thanks for checking in!")
                .font(.headline)
            HStack {
                ForEach(FamilyMood.range, id: \.self) { rating in
                    let chosen = today.map { Int($0.rating) == rating } ?? false
                    Button {
                        do { try service.checkInMood(rating, by: me) } catch { self.error = error.localizedDescription }
                    } label: {
                        Text(FamilyMood.face(rating))
                            .font(.system(size: chosen ? 38 : 30))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(chosen ? Theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .opacity(today == nil || chosen ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "\(rating) of 5"))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            if today != nil {
                Text(!showsWhereToLook ? "Tap another face to change it."
                     : me.isParent ? "Tap another face to change it. See how everyone's doing under Family → Family mood."
                     : "Tap another face to change it. Your grown-ups can see how you feel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .errorAlert($error)
    }
}

/// The family's mood over time, what seems to help, and ideas for a lift.
/// Parents see everyone's check-ins and notes; kids see the family average and their own.
struct FamilyMoodView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var planned: Set<String> = []
    @State private var error: String?

    var body: some View {
        let trend = FamilyMood.trend(days: 14, in: household)
        List {
            Section { MoodCheckInCard(me: me, showsWhereToLook: false) }

            Section {
                if trend.isEmpty {
                    Text("Check in for a few days to see the family's mood here.").foregroundStyle(.secondary)
                } else {
                    Chart(trend, id: \.day) { point in
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("Mood", point.average))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value("Mood", point.average))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: 1...5)
                    .chartYAxis {
                        AxisMarks(values: [1, 3, 5]) { value in
                            AxisGridLine()
                            AxisValueLabel { Text(FamilyMood.face(value.as(Int.self) ?? 3)) }
                        }
                    }
                    .frame(height: 160)
                    .accessibilityLabel("Family mood over the last two weeks")
                }
            } header: {
                Text("Last two weeks")
            }

            if me.isParent {
                Section("Today") {
                    ForEach(household.memberList) { member in
                        PersonMoodRow(member: member)
                    }
                }
                let notes = MoodInsights.workloadNotes(for: household)
                if !notes.isEmpty {
                    Section("Worth a look") {
                        ForEach(notes, id: \.self) { Label($0, systemImage: "scalemass") }
                    }
                }
            } else if let mine = FamilyMood.average(for: me, days: 7) {
                Section("You this week") {
                    LabeledContent("Your average", value: "\(FamilyMood.face(Int(mine.rounded()))) \(mine.formatted(.number.precision(.fractionLength(1))))")
                }
            }

            Section {
                let insights = MoodInsights.insights(for: household)
                if insights.isEmpty {
                    Text("After a few weeks of check-ins, patterns show up here, like which habits go with happier weeks.")
                        .foregroundStyle(.secondary)
                }
                ForEach(insights) { Label($0.text, systemImage: "sparkles") }
            } header: {
                Text("What we've noticed")
            } footer: {
                Text("These show what tends to happen together, not what causes what. Worked out on your devices; nothing leaves your family.")
            }

            Section {
                ForEach(MoodInsights.suggestedBoosters(for: household), id: \.booster.id) { item in
                    HStack {
                        Text(item.booster.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.booster.title)
                            if let before = item.before {
                                Text("Family mood was \(before.formatted(.number.precision(.fractionLength(1)))) the last times you did this")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if me.isParent {
                            Button(planned.contains(item.booster.id) ? "Planned" : "Plan it") { plan(item.booster) }
                                .buttonStyle(.bordered)
                                .disabled(planned.contains(item.booster.id))
                        }
                    }
                }
            } header: {
                Text("Mood boosters")
            } footer: {
                Text(me.isParent ? "Planning one puts it on today's list so the kids can see it's coming."
                                 : "Like one? Ask a grown-up!")
            }
        }
        .navigationTitle("Family Mood")
        .errorAlert($error)
    }

    private func plan(_ booster: MoodInsights.Booster) {
        do {
            try service.planBooster(booster, by: me)
            planned.insert(booster.id)
        } catch { self.error = error.localizedDescription }
    }
}

private struct PersonMoodRow: View {
    @ObservedObject var member: Member

    var body: some View {
        let today = FamilyMood.checkIn(by: member, on: Date())
        HStack(spacing: 12) {
            Avatar(member: member, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                if let note = today?.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                if let week = FamilyMood.average(for: member, days: 7) {
                    Text("This week: \(week.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(today.map { FamilyMood.face(Int($0.rating)) } ?? "–").font(.title)
                .accessibilityLabel(today.map { String(localized: "\(Int($0.rating)) of 5") } ?? String(localized: "No check-in yet"))
        }
    }
}
