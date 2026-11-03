import SwiftUI

/// The top of a kid's chore list: the goat cheering them on, their points and streak,
/// how today is going, and how close they are to what they're saving for.
struct KidHero: View {
    @ObservedObject var member: Member
    /// Today's chores still to do, and those already turned in today.
    let left: Int
    let doneToday: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    private var allDone: Bool { left == 0 && doneToday > 0 }

    private var cheer: String {
        if allDone { return String(localized: "All done today! You're the GOAT.") }
        if doneToday == 0 { return String(localized: "Let's do this, \(member.displayName)!") }
        return String(localized: "\(left) to go. You've got this!")
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 12) {
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                Goat(mood: allDone ? .party : .cheer, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hi, \(member.displayName)!").font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cheer).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))) {
                stat(value: Text("\(member.available)").foregroundStyle(Theme.coral), label: "points")
                    .accessibilityLabel("\(member.available) points")
                if case let streak = member.streak(), streak > 0 {
                    stat(value: Text(verbatim: "🔥\(streak)").foregroundStyle(Theme.gold), label: "day streak")
                        .accessibilityLabel(String(localized: "\(streak)-day streak"))
                }
                if left + doneToday > 0 {
                    stat(value: Text(verbatim: "\(doneToday)/\(left + doneToday)").foregroundStyle(Theme.accent), label: "done today")
                        .accessibilityLabel(String(localized: "\(doneToday) of \(left + doneToday) done today"))
                }
            }
            RewardPath(member: member)
        }
        .padding()
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.vertical, 4)
    }

    private func stat(value: Text, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            value.font(.system(.title2, design: .rounded, weight: .heavy)).contentTransition(.numericText())
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
    }
}

/// A track from where the kid is to the reward they're saving for, with the goat sailing along it.
struct RewardPath: View {
    @ObservedObject var member: Member

    var body: some View {
        if let goal = member.goal {
            let reached = member.available >= Int(goal.cost)
            let progress = min(1, max(0, member.goalProgress))
            VStack(alignment: .leading, spacing: 8) {
                Text(reached
                     ? String(localized: "You can get \(goal.displayTitle)!")
                     : String(localized: "\(max(0, Int(goal.cost) - member.available)) more points for \(goal.displayEmoji + " " + goal.displayTitle)."))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { proxy in
                    let goatSize: CGFloat = 40
                    let travel = max(0, proxy.size.width - goatSize - 36)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.goldFill.opacity(0.25)).frame(height: 12)
                        Capsule().fill(reached ? Color.green : Theme.goldFill)
                            .frame(width: goatSize / 2 + travel * progress, height: 12)
                        Text(goal.displayEmoji)
                            .font(.title2)
                            .frame(width: 36, height: 36)
                            .background(Theme.card, in: Circle())
                            .overlay(Circle().stroke(reached ? Color.green : Theme.goldFill, lineWidth: 2))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Goat(mood: reached ? .party : .cheer, size: goatSize)
                            .offset(x: travel * progress, y: -8)
                    }
                    .frame(height: proxy.size.height)
                }
                .frame(height: 44)
                .animation(.spring(duration: 0.6), value: progress)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reached
                ? String(localized: "You can get \(goal.displayTitle)!")
                : String(localized: "\(max(0, member.available)) of \(goal.cost) points"))
        } else {
            Label("Pick a reward to save for in Rewards.", systemImage: "star")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// One of a kid's chores as a big, friendly card. Simple chores can be finished right here;
/// routines and photo chores open so the kid can tick steps or add the photo.
struct KidChoreCard: View {
    @ObservedObject var chore: Chore
    let me: Member
    let onDone: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric private var tile: CGFloat = 56

    private var canFinishHere: Bool {
        chore.status == .todo && !chore.isRoutine && !chore.photoRequired
            && (chore.assignee == me || chore.isUnclaimed)
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Text(chore.emoji ?? "✅")
                .font(.system(size: tile * 0.55))
                .frame(width: tile, height: tile)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.displayTitle).font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                if !chore.isFamilyJob {
                    Text(verbatim: "+\(chore.points)")
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.coral)
                        .accessibilityLabel("\(Int(chore.points)) points")
                }
                if canFinishHere {
                    Button(action: onDone) {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Mark \(chore.displayTitle) done"))
                } else if chore.status == .pendingReview {
                    Image(systemName: "hourglass")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Waiting for approval")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(chore.status == .pendingReview ? 0.75 : 1)
    }

    @ViewBuilder private var details: some View {
        let parts = HStack(spacing: 8) {
            // The section already says morning, afternoon or evening; only a late or future date is news.
            if chore.status == .todo, let due = dueText(for: chore),
               chore.isOverdue || !Calendar.current.isDateInToday(chore.dueDate ?? Date()) {
                Text(due).foregroundStyle(chore.isOverdue ? Color.red : Color.secondary)
            }
            if let minutes = chore.minutes { Label("\(minutes) min", systemImage: "stopwatch") }
        }
        parts.font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        if chore.isRoutine && chore.status == .todo {
            Text("\(chore.doneSteps.count) of \(chore.steps.count) steps").font(.caption).foregroundStyle(.secondary)
        }
        if chore.status == .todo && (chore.photoRequired || chore.wasSentBack || chore.extraCredit || chore.isFamilyJob) {
            HStack(spacing: 4) {
                if chore.wasSentBack { StatusChip(text: "Sent back", color: .orange) }
                if chore.photoRequired { StatusChip(text: "Photo", color: .purple) }
                if chore.extraCredit { StatusChip(text: "Extra credit", color: .green) }
                if chore.isFamilyJob { StatusChip(text: "Family job", color: .teal) }
            }
        }
    }
}
