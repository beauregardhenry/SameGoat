import SwiftUI
import CoreData

struct ChoresView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var chores: FetchedResults<Chore>
    @State private var showingNew = false
    @State private var showingLibrary = false
    @State private var showingProject = false
    @State private var showingSpoons = false
    /// Counts chores a kid finishes from their list, to buzz the phone each time.
    @State private var finishedHere = 0
    @State private var error: String?

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        // Kids see their own chores plus the up-for-grabs pool; parents see everyone's.
        let predicate = me.isParent
            ? NSPredicate(format: "household == %@", household)
            : NSPredicate(format: "household == %@ AND (assignee == %@ OR (upForGrabs == YES AND assignee == nil))", household, me)
        _chores = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Chore.createdAt, ascending: false)],
            predicate: predicate,
            animation: .default)
    }

    private func dueSorted(_ list: [Chore]) -> [Chore] {
        list.sorted { a, b in
            switch (a.dueAt(), b.dueAt()) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
        }
    }

    private var waiting: [Chore] { chores.filter { $0.status == .pendingReview } }
    /// Open chores outside any project; projects list their own.
    private var open: [Chore] { chores.filter { $0.status == .todo && $0.projectID == nil && !$0.isMenuOption } }
    /// Each kid's choice menus: options still on offer, grouped by menu.
    private var menus: [[Chore]] {
        Dictionary(grouping: chores.filter { $0.status == .todo && $0.isMenuOption }, by: { $0.menuID })
            .values.map { $0.sorted { $0.displayTitle < $1.displayTitle } }
            .sorted { ($0.first?.assignee?.displayName ?? "") < ($1.first?.assignee?.displayName ?? "") }
    }
    private var onHold: Bool { household.overridingProject() != nil }
    private var todo: [Chore] { onHold ? [] : dueSorted(open.filter { !$0.isUnclaimed && !$0.extraCredit }) }
    private var extra: [Chore] { onHold ? [] : dueSorted(open.filter { !$0.isUnclaimed && $0.extraCredit }) }
    private var grabs: [Chore] { onHold ? [] : dueSorted(open.filter(\.isUnclaimed)) }
    /// What the grown-ups are doing today, so kids see that everyone helps.
    private var grownUps: [Chore] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return ((household.chores as? Set<Chore>) ?? [])
            .filter { $0.assignee?.isParent == true && $0.status == .todo && ($0.dueDate ?? .distantPast) < tomorrow }
            .sorted { ($0.assignee?.displayName ?? "", $0.displayTitle) < ($1.assignee?.displayName ?? "", $1.displayTitle) }
    }

    /// Today's chores a kid still has to do (undated ones included), and those they've turned in today.
    private var leftToday: Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return todo.filter { ($0.dueDate ?? .distantPast) < tomorrow }.count
    }
    private var doneToday: Int {
        chores.filter { $0.status != .todo && $0.assignee == me && Calendar.current.isDateInToday($0.completedAt ?? .distantPast) }.count
    }

    /// Regular chores waiting while a project comes first.
    private var later: [Chore] { onHold ? dueSorted(open) : [] }
    private var done: [Chore] {
        Array(chores.filter { $0.status == .approved }
            .sorted { ($0.reviewedAt ?? .distantPast) > ($1.reviewedAt ?? .distantPast) }
            .prefix(30))
    }

    var body: some View {
        Group {
            if !me.isParent && me.bigPicture {
                BigPictureView(household: household, me: me, chores: Array(chores))
            } else {
                list
            }
        }
        .navigationTitle(me.isParent ? "Chores" : "My Chores")
        .navigationDestination(for: Chore.self) { ChoreDetailView(chore: $0, me: me) }
        .toolbar {
            if household.has(.energy) {
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingSpoons = true } label: { Label("How much energy?", systemImage: "battery.50percent") }
                }
            }
            if me.isParent && household.has(.projects) {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingProject = true } label: { Label("New Project", systemImage: "hammer") }
                }
            }
            if me.isParent {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingLibrary = true } label: { Label("Chore Ideas", systemImage: "lightbulb") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Label("New Chore", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            ChoreEditorView(household: household, me: me, chore: nil)
        }
        .sheet(isPresented: $showingSpoons) {
            SpoonsView(me: me, household: household)
        }
        .sheet(isPresented: $showingProject) {
            ProjectEditorView(household: household, me: me)
        }
        .sheet(isPresented: $showingLibrary) {
            ChoreLibraryView(household: household, me: me)
        }
    }

    private var list: some View {
        List {
            if household.upcomingPause() != nil {
                Section { PauseBanner(household: household) }
            }
            if !me.isParent {
                Section { KidHero(member: me, left: leftToday, doneToday: doneToday) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if household.has(.mood) && FamilyMood.checkIn(by: me, on: Date()) == nil {
                Section { MoodCheckInCard(me: me) }
            }
            ForEach(household.activeProjects()) { project in
                ProjectSection(project: project, household: household, me: me)
            }
            if me.isParent {
                choreSection("Waiting for review", waiting)
                choreSection("To do", todo)
                choreSection("Extra credit", extra)
                choreSection("Up for grabs", grabs)
            } else {
                // A kid's list reads like their day: morning, afternoon, evening, then anytime.
                ForEach(TimeOfDay.allCases) { time in
                    kidSection(LocalizedStringKey(time.title), todo.filter { $0.timeOfDay == time }, icon: time.icon)
                }
                kidSection(todo.contains { $0.timeOfDay != nil } ? "Anytime" : "To do", todo.filter { $0.timeOfDay == nil })
                kidSection("Up for grabs", grabs, icon: "hand.raised")
                kidSection("Extra credit", extra, icon: "plus.circle")
                kidSection("Waiting for approval", waiting, icon: "hourglass")
                if !grownUps.isEmpty {
                    Section {
                        ForEach(grownUps) { ChoreRow(chore: $0, showAssignee: true) }
                    } header: {
                        Label("The grown-ups today", systemImage: "person.2")
                    } footer: {
                        Text("Everyone in the family helps.")
                    }
                }
            }
            ForEach(menus, id: \.first?.objectID) { options in
                if let first = options.first { menuSection(options, first: first) }
            }
            choreSection("After the project", later, icon: "pause.circle")
            choreSection("Done", done)
        }
        .sensoryFeedback(.success, trigger: finishedHere)
        .errorAlert($error)
        .overlay {
            if chores.isEmpty {
                GoatEmptyView(
                    title: me.isParent ? "No chores yet" : "Nothing to do!",
                    mood: me.isParent ? .curious : .cheer,
                    description: Text(me.isParent ? "Tap + to assign the first chore, or start from a list of ideas by age."
                                                  : "When a parent gives you a chore, it shows up here.")
                ) {
                    if me.isParent {
                        Button("Browse Chore Ideas") { showingLibrary = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    /// "Choose 2 of these": a kid picks; a parent sees what's on offer.
    private func menuSection(_ options: [Chore], first: Chore) -> some View {
        let needed = Int(first.menuPick)
        let picked = ChoiceMenu.pickedCount(like: first)
        return Section {
            ForEach(options) { option in
                HStack {
                    NavigationLink(value: option) { ChoreRow(chore: option, showAssignee: me.isParent) }
                    if !me.isParent {
                        Button("Pick") {
                            try? service.pick(option, by: me)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "Pick \(option.displayTitle)"))
                    }
                }
            }
        } header: {
            Label {
                if me.isParent, let kid = first.assignee {
                    Text("\(kid.displayName) chooses \(needed) (\(picked) picked)")
                } else {
                    Text("Choose \(needed - picked) more")
                }
            } icon: { Image(systemName: "hand.point.up.left") }
        } footer: {
            if !me.isParent && ChoiceMenu.prefersEasy(me) {
                Text("You've picked the easiest one lately. Try a harder one: more points means more free time!")
            } else if !me.isParent {
                Text("You choose which ones to do this week.")
            }
        }
    }

    /// A kid's chores as big cards they can finish with one tap.
    @ViewBuilder
    private func kidSection(_ title: LocalizedStringKey, _ list: [Chore], icon: String? = nil) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { chore in
                    ZStack {
                        // Tapping the card opens the chore; the hidden link keeps the card free of a chevron row.
                        NavigationLink(value: chore) { EmptyView() }.opacity(0)
                        KidChoreCard(chore: chore, me: me) { finish(chore) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .choreEditing(chore, household: household, me: me)
                }
            } header: {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
        }
    }

    private func finish(_ chore: Chore) {
        do {
            try withAnimation(.spring) { try service.markComplete(chore, by: me, note: nil, photo: nil) }
            finishedHere += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func choreSection(_ title: LocalizedStringKey, _ list: [Chore], icon: String? = nil) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { chore in
                    NavigationLink(value: chore) {
                        ChoreRow(chore: chore, showAssignee: me.isParent)
                    }
                    .choreEditing(chore, household: household, me: me)
                }
            } header: {
                if let icon { Label(title, systemImage: icon) } else { Text(title) }
            }
        }
    }
}

struct BalanceCard: View {
    @ObservedObject var member: Member
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "24 points ($2.40) · 4 on hold"
    private var pointsLine: String {
        var line = String(localized: "\(member.available) points")
        if let money = member.household?.moneyText(for: member.available) { line += " (\(money))" }
        if member.reserved > 0 { line += " · " + String(localized: "\(member.reserved) on hold") }
        return line
    }

    var body: some View {
        let streak = member.streak()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Avatar(member: member, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hi, \(member.displayName)!").font(.title3.bold())
                    Text(pointsLine)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if streak > 0 {
                        Text("🔥 \(streak)-day streak").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                    }
                }
                Spacer()
                // The line above already says the points; at the largest text sizes there's no room for both.
                if !typeSize.isAccessibilitySize {
                    Text("\(member.available)")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.coral)
                        .contentTransition(.numericText())
                        .accessibilityHidden(true)
                }
            }
            if let goal = member.goal {
                GoalProgress(member: member, goal: goal)
            }
        }
        .padding()
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct GoalProgress: View {
    @ObservedObject var member: Member
    let goal: Reward

    var body: some View {
        let reached = member.available >= Int(goal.cost)
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer()
                    amount(reached)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    amount(reached)
                }
            }
            ProgressView(value: member.goalProgress)
                .tint(reached ? .green : Theme.goldFill)
                .accessibilityHidden(true)
        }
    }

    private var title: some View {
        Text("Saving for \(goal.displayEmoji) \(goal.displayTitle)").font(.subheadline.weight(.medium))
    }

    private func amount(_ reached: Bool) -> some View {
        Text(reached ? "Ready!" : "\(max(0, member.available)) / \(goal.cost)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(reached ? Color.green : Color.secondary)
            .accessibilityLabel(reached ? "You have enough!" : "\(max(0, member.available)) of \(goal.cost) points")
    }
}

struct ChoreRow: View {
    @ObservedObject var chore: Chore
    var showAssignee: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest text sizes the points move under the title instead of squeezing it.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if showAssignee, let assignee = chore.assignee {
                Avatar(member: assignee, size: 38)
            } else if showAssignee, chore.isUnclaimed {
                Image(systemName: "hand.raised.circle.fill")
                    .font(.title).foregroundStyle(.orange).frame(width: 38)
                    .accessibilityLabel("Up for grabs")
            } else if let emoji = chore.emoji, chore.status == .todo {
                // A picture for kids who can't read yet.
                Text(emoji).font(.system(size: 28)).frame(width: 38).accessibilityHidden(true)
            } else {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 38)
                    .accessibilityLabel(statusName)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(chore.displayTitle).font(.headline)
                HStack(spacing: 6) {
                    if showAssignee, let assignee = chore.assignee { Text(assignee.displayName) }
                    if showAssignee, chore.isUnclaimed { Text("Anyone") }
                    if let due = dueText(for: chore) {
                        Text(due).foregroundStyle(chore.isOverdue ? Color.red : Color.secondary)
                    }
                    if chore.takesTurns {
                        Image(systemName: "arrow.triangle.2.circlepath").accessibilityLabel("Taking turns")
                    } else if chore.recurrence.isRepeating {
                        Image(systemName: "repeat").accessibilityLabel("Repeats")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let effort = chore.effortLabel, chore.status == .todo {
                    Label(effort, systemImage: "stopwatch").font(.caption).foregroundStyle(.secondary)
                }
                if chore.isRoutine && chore.status == .todo {
                    Text("\(chore.doneSteps.count) of \(chore.steps.count) steps")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if chore.status == .todo && (chore.stretch || chore.extraCredit) {
                    HStack(spacing: 4) {
                        if chore.stretch { StatusChip(text: "Stretch", color: .purple) }
                        if chore.extraCredit { StatusChip(text: "Extra credit", color: .green) }
                    }
                }
                if chore.wasSentBack { StatusChip(text: "Sent back", color: .orange) }
                if chore.status == .pendingReview && showAssignee { StatusChip(text: "Needs review", color: .blue) }
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            if chore.isFamilyJob && chore.status != .approved {
                StatusChip(text: "Family job", color: .teal)
            } else {
                PointsBadge(points: Int(chore.status == .approved ? chore.awardedPoints : chore.points))
            }
        }
        .padding(.vertical, 2)
        // One VoiceOver stop per chore: "Dishes, Ava, Today, Repeats, 5 points".
        .accessibilityElement(children: .combine)
    }

    private var statusName: String {
        switch chore.status {
        case .todo: chore.isOverdue ? String(localized: "Overdue") : String(localized: "To do")
        case .pendingReview: String(localized: "Waiting for approval")
        case .approved: String(localized: "Done")
        }
    }

    private var statusIcon: String {
        switch chore.status {
        case .todo: "circle"
        case .pendingReview: "hourglass"
        case .approved: "checkmark.circle.fill"
        }
    }
    private var statusColor: Color {
        switch chore.status {
        case .todo: chore.isOverdue ? .red : .secondary
        case .pendingReview: .blue
        case .approved: .green
        }
    }
}
