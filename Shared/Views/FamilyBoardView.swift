import SwiftUI
import CoreData

/// Every kid's chores for today side by side, for a tablet on the kitchen counter.
/// Tapping a chore marks it done for that kid; up-for-grabs chores ask who did it.
struct FamilyBoardView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var chores: FetchedResults<Chore>
    @State private var finishing: (chore: Chore, kid: Member)?
    @State private var choosingKid: Chore?
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _chores = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Chore.createdAt, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default)
    }

    private var endOfToday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    /// Open chores due by tonight (or undated), then today's finished ones, in time-of-day order.
    private func today(_ list: [Chore]) -> [Chore] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return list.filter { chore in
            switch chore.status {
            case .todo: (chore.dueDate ?? .distantPast) < endOfToday
            case .pendingReview, .approved: (chore.completedAt ?? .distantPast) >= startOfToday
            }
        }
        .sorted { a, b in
            if (a.status == .todo) != (b.status == .todo) { return a.status == .todo }
            let order = { (c: Chore) in c.timeOfDay.flatMap { TimeOfDay.allCases.firstIndex(of: $0) } ?? 3 }
            return (order(a), a.displayTitle) < (order(b), b.displayTitle)
        }
    }

    private var pool: [Chore] { today(chores.filter(\.isUnclaimed)) }

    private static let minColumnWidth: CGFloat = 250

    var body: some View {
        GeometryReader { proxy in
            // Columns share the width when they fit and scroll sideways when they don't.
            let count = CGFloat(household.kids.count + (pool.isEmpty ? 0 : 1))
            let width = max(Self.minColumnWidth, (proxy.size.width - 32 - 16 * max(0, count - 1)) / max(1, count))
            ScrollView(.vertical) {
                ScrollView(.horizontal) {
                    board(columnWidth: width)
                }
            }
        }
        .background(Color.secondary.opacity(0.06))
        .overlay {
            if household.kids.isEmpty {
                ContentUnavailableView("No kids yet", systemImage: "person.2", description: Text("Add a kid in the Family tab first."))
            }
        }
        .navigationTitle("Family Board")
        .confirmationDialog(
            finishing.map { String(localized: "Mark “\($0.chore.displayTitle)” done for \($0.kid.displayName)?") } ?? "",
            isPresented: Binding(get: { finishing != nil }, set: { if !$0 { finishing = nil } }),
            titleVisibility: .visible
        ) {
            if let (chore, kid) = finishing {
                Button("Done!") { finish(chore, by: kid) }
            }
        }
        .confirmationDialog(
            String(localized: "Who did it?"),
            isPresented: Binding(get: { choosingKid != nil }, set: { if !$0 { choosingKid = nil } }),
            titleVisibility: .visible
        ) {
            if let chore = choosingKid {
                ForEach(household.kids) { kid in
                    Button("\(kid.displayEmoji) \(kid.displayName)") { finish(chore, by: kid) }
                }
            }
        }
        .errorAlert($error)
    }

    private func board(columnWidth: CGFloat) -> some View {
            HStack(alignment: .top, spacing: 16) {
                ForEach(household.kids) { kid in
                    column(header: AnyView(KidHeader(kid: kid)), width: columnWidth,
                           chores: today(chores.filter { $0.assignee == kid })) { chore in
                        if chore.isRoutine || chore.photoRequired {
                            error = String(localized: "Open \(chore.displayTitle) on \(kid.displayName)'s list to tick its steps or add a photo.")
                        } else {
                            finishing = (chore, kid)
                        }
                    }
                }
                if !pool.isEmpty {
                    column(header: AnyView(Label("Up for grabs", systemImage: "hand.raised.fill")
                        .font(.title3.bold()).foregroundStyle(.orange)), width: columnWidth,
                           chores: pool) { choosingKid = $0 }
                }
            }
            .padding()
    }

    private func column(header: AnyView, width: CGFloat, chores: [Chore], onTap: @escaping (Chore) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if chores.isEmpty {
                Text("All done today! 🎉").foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(chores) { chore in
                BoardCard(chore: chore) { if chore.status == .todo { onTap(chore) } }
                    .choreEditing(chore, household: household, me: me)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func finish(_ chore: Chore, by kid: Member) {
        do { try service.markComplete(chore, by: kid, note: nil, photo: nil) } catch { self.error = error.localizedDescription }
        finishing = nil
        choosingKid = nil
    }
}

private struct KidHeader: View {
    @ObservedObject var kid: Member

    var body: some View {
        HStack(spacing: 10) {
            Avatar(member: kid, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(kid.displayName).font(.title3.bold())
                Text("\(kid.available) points").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if case let streak = kid.streak(), streak > 0 {
                Text(verbatim: "🔥\(streak)").font(.headline).foregroundStyle(.orange)
            }
        }
    }
}

private struct BoardCard: View {
    @ObservedObject var chore: Chore
    let onTap: () -> Void

    var body: some View {
        let done = chore.status != .todo
        Button(action: onTap) {
            HStack(spacing: 10) {
                Group {
                    if let emoji = chore.emoji {
                        Text(emoji).font(.system(size: 30))
                    } else {
                        Image(systemName: done ? "checkmark.circle" : "circle").font(.system(size: 26)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chore.displayTitle).font(.headline).strikethrough(done)
                    if let time = chore.timeOfDay { Label(time.title, systemImage: time.icon).font(.caption).foregroundStyle(.secondary) }
                    if chore.status == .pendingReview { Text("Waiting for approval").font(.caption).foregroundStyle(.blue) }
                }
                Spacer(minLength: 4)
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                } else if !chore.isFamilyJob {
                    PointsBadge(points: Int(chore.points))
                }
            }
            .padding(10)
            .background(done ? Color.green.opacity(0.08) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(done ? "" : String(localized: "Marks it done"))
    }
}
