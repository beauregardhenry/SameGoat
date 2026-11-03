import SwiftUI
import Charts

/// This week for each kid (or just yourself, for a kid), with the last few weeks charted.
struct RecapView: View {
    let household: Household
    let me: Member

    private var weeks: [WeeklyRecap.KidWeek] {
        WeeklyRecap.summaries(for: me.isParent ? household.kids : [me])
    }

    var body: some View {
        let weeks = weeks
        List {
            Section {
                Text(WeeklyRecap.headline(weeks)).font(.headline)
            }
            ForEach(weeks) { week in
                Section {
                    HStack(spacing: 12) {
                        Text(week.emoji).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(week.name).font(.headline)
                            Text("\(week.choresDone) chores done")
                                + Text(verbatim: week.minutes > 0 ? " · " + String(localized: "\(week.minutes) min") : "")
                                + Text(verbatim: week.streak > 0 ? " · 🔥 \(week.streak)" : "")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(week.points)").font(.title2.bold()).foregroundStyle(Theme.coral)
                            Text("this week").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Chart(week.history, id: \.start) { item in
                        BarMark(x: .value("Week", item.start, unit: .weekOfYear),
                                y: .value("Points", item.points))
                            .foregroundStyle(item.start == week.history.last?.start ? Theme.coral : Theme.coral.opacity(0.35))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .frame(height: 120)
                    .accessibilityLabel("Points over the last \(WeeklyRecap.weeksShown) weeks")
                }
            }
        }
        .navigationTitle(me.isParent ? "Weekly Recap" : "Your Week")
    }
}
