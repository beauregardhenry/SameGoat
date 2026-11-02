import SwiftUI

/// A little one's chores as big picture tiles: today's chores, then what's done.
struct BigPictureView: View {
    let household: Household
    @ObservedObject var me: Member
    let chores: [Chore]

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 16)] }

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? Date() }

    private var toDo: [Chore] {
        chores.filter { $0.status == .todo && !$0.isMenuOption && ($0.dueDate ?? .distantPast) < tomorrow && !$0.isOnHold() }
            .sorted { ($0.timeOfDay.flatMap { TimeOfDay.allCases.firstIndex(of: $0) } ?? 3, $0.displayTitle)
                < ($1.timeOfDay.flatMap { TimeOfDay.allCases.firstIndex(of: $0) } ?? 3, $1.displayTitle) }
    }
    private var doneToday: [Chore] {
        chores.filter { $0.status != .todo && ($0.completedAt ?? .distantPast) >= startOfToday }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BalanceCard(member: me)
                if toDo.isEmpty {
                    VStack(spacing: 8) {
                        Text("🎉").font(.system(size: 72))
                        Text("All done today!").font(.title.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(toDo) { tile($0, done: false) }
                    ForEach(doneToday) { tile($0, done: true) }
                }
            }
            .padding()
        }
        .background(Color.secondary.opacity(0.06))
    }

    private func tile(_ chore: Chore, done: Bool) -> some View {
        NavigationLink(value: chore) {
            VStack(spacing: 10) {
                Text(chore.emoji ?? (done ? "✅" : "⭐️"))
                    .font(.system(size: 64))
                    .opacity(done ? 0.5 : 1)
                Text(chore.displayTitle)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .strikethrough(done)
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                } else if !chore.isFamilyJob {
                    PointsBadge(points: Int(chore.points))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(done ? Color.green.opacity(0.4) : Theme.accent.opacity(0.25), lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? String(localized: "\(chore.displayTitle), done") : chore.displayTitle)
    }
}
