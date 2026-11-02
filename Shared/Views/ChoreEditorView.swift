import SwiftUI

/// Creates a chore (for one or more kids) or edits one that hasn't been turned in.
struct ChoreEditorView: View {
    let household: Household
    let me: Member
    let chore: Chore?

    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HouseholdService.ChoreDraft
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var selected: Set<Member>
    /// Points follow the effort until the parent sets them by hand.
    @State private var pointsFollowEffort: Bool
    @State private var error: String?

    init(household: Household, me: Member, chore: Chore?) {
        self.household = household
        self.me = me
        self.chore = chore
        var draft = HouseholdService.ChoreDraft()
        if let chore {
            draft.title = chore.title ?? ""
            draft.notes = chore.notes ?? ""
            draft.points = Int(chore.points)
            draft.recurrence = chore.recurrence
            draft.dueDate = chore.dueDate
            draft.takeTurns = chore.takesTurns
            draft.autoApprove = chore.autoApprove
            draft.steps = chore.steps
            draft.photoRequired = chore.photoRequired
            draft.minutes = chore.minutes
            draft.difficulty = chore.difficulty
            draft.upForGrabs = chore.upForGrabs
            draft.timeOfDay = chore.timeOfDay
            draft.emoji = chore.emoji
            draft.whyItHelps = chore.whyItHelps ?? ""
            draft.tips = chore.tips ?? ""
            draft.skill = chore.skill
            draft.stretch = chore.stretch
            draft.extraCredit = chore.extraCredit
            draft.dueWithinWeek = chore.dueWithinWeek
        }
        _draft = State(initialValue: draft)
        let suggested = Effort.suggestedPoints(minutes: draft.minutes, difficulty: draft.difficulty,
                                               rate: Int(household.effortRate), skill: draft.skill)
        _pointsFollowEffort = State(initialValue: chore == nil || suggested == draft.points)
        _hasDue = State(initialValue: chore?.dueDate != nil)
        _due = State(initialValue: chore?.dueDate ?? Date())
        _hasTime = State(initialValue: chore?.dueTime != nil)
        // The picker needs a date; only its hour and minute are used. New times start at 5pm.
        let minutes = chore?.dueTime ?? 17 * 60
        _time = State(initialValue: Calendar.current.date(byAdding: .minute, value: minutes,
                                                          to: Calendar.current.startOfDay(for: Date())) ?? Date())
        if let chore, chore.takesTurns {
            _selected = State(initialValue: Set(chore.rotation))
        } else {
            _selected = State(initialValue: chore?.assignee.map { [$0] } ?? [])
        }
    }

    private var isEditing: Bool { chore != nil }

    private var suggestedPoints: Int? {
        Effort.suggestedPoints(minutes: draft.minutes, difficulty: draft.difficulty,
                               rate: Int(household.effortRate), skill: draft.skill)
    }

    private var effortSection: some View {
        Section {
            Picker("Time", selection: $draft.minutes) {
                Text("Not set").tag(Int?.none)
                ForEach(Effort.timeChoices, id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
            }
            Picker("Difficulty", selection: $draft.difficulty) {
                Text("Not set").tag(Difficulty?.none)
                ForEach(Difficulty.allCases) { Text($0.title).tag(Difficulty?.some($0)) }
            }
            Picker("Problem-solving", selection: $draft.skill) {
                Text("Not set").tag(Int?.none)
                ForEach(1...5, id: \.self) { Text(String(repeating: "⭐️", count: $0)).tag(Int?.some($0)) }
            }
        } header: {
            Text("Effort")
        } footer: {
            if let suggestedPoints, suggestedPoints != draft.points {
                HStack {
                    Text("Suggested from effort: \(suggestedPoints) points.")
                    Button("Use") { draft.points = suggestedPoints; pointsFollowEffort = true }
                        .font(.footnote.weight(.semibold))
                }
            } else if suggestedPoints != nil {
                Text("Points match the effort. Change them if you like.")
            } else {
                Text("Set how long it takes and how hard it is to get a fair points suggestion.")
            }
        }
        .onChange(of: draft.minutes) { _, _ in followEffort() }
        .onChange(of: draft.skill) { _, _ in followEffort() }
        .onChange(of: draft.difficulty) { _, _ in followEffort() }
    }

    private func followEffort() {
        if pointsFollowEffort, let suggestedPoints { draft.points = suggestedPoints }
    }

    /// "40 min this week" beside each kid, so the work can be spread fairly.
    private func workload(_ kid: Member) -> String? {
        let minutes = Effort.openMinutes(for: kid)
        return minutes > 0 ? String(localized: "\(minutes) min to do this week") : nil
    }

    private var turnsHint: String {
        guard draft.takeTurns else { return String(localized: "Each person gets their own copy to complete.") }
        guard draft.recurrence.isRepeating else {
            return String(localized: "Choose how often it repeats below; it moves to the next person each time.")
        }
        let names = household.kids.filter { selected.contains($0) }.map(\.displayName).joined(separator: " → ")
        return String(localized: "One chore that moves to the next person each time it repeats: \(names).")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $draft.title)
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                    ChoreEmojiPicker(selection: $draft.emoji)
                    TextField("How it helps the family (optional)", text: $draft.whyItHelps, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Tips for doing it well (optional)", text: $draft.tips, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Chore")
                } footer: {
                    Text("A picture helps kids who can't read yet. Kids see how it helps and your tips on the chore, so you don't have to say it every time.")
                }

                effortSection

                Section {
                    HStack {
                        Text("Points")
                        Spacer()
                        TextField("Points", value: $draft.points, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Stepper("Points", value: $draft.points, in: 0...10_000, step: 5)
                            .labelsHidden()
                    }
                    .onChange(of: draft.points) { _, points in
                        // Typing or stepping a different number means the parent has chosen the points.
                        if points != suggestedPoints { pointsFollowEffort = false }
                    }
                    Toggle("Approve automatically", isOn: $draft.autoApprove)
                    Toggle("Extra credit", isOn: $draft.extraCredit)
                    Toggle("Stretch chore", isOn: $draft.stretch)
                    Toggle("Needs a photo", isOn: $draft.photoRequired)
                } footer: {
                    Text(draft.autoApprove
                         ? "Points are awarded as soon as it's marked done. Good for small daily habits."
                         : "Awarded only after a parent confirms the chore is done.")
                    + Text(" ")
                    + Text(draft.extraCredit ? "Extra credit is optional: it earns points but is never overdue." : "")
                    + Text(draft.stretch ? " A stretch chore is a step up, and kids see it as a challenge." : "")
                }

                Section {
                    ForEach(draft.steps.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "circle").foregroundStyle(.tertiary).accessibilityHidden(true)
                            TextField("Step \(index + 1)", text: $draft.steps[index])
                            Button { draft.steps.remove(at: index) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove step \(index + 1)")
                        }
                    }
                    if draft.steps.count < HouseholdService.maxSteps {
                        Button("Add a step", systemImage: "plus.circle") { draft.steps.append("") }
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text(draft.steps.isEmpty
                         ? "Optional. Add steps to make a routine, like a morning checklist."
                         : "They tick off each step before they can say it's done.")
                }

                Section(isEditing ? "Assigned to" : "Assign to") {
                    if household.kids.isEmpty {
                        Text("Add a kid in the Family tab first.").foregroundStyle(.secondary)
                    }
                    Button {
                        draft.upForGrabs.toggle()
                        if draft.upForGrabs { selected = []; draft.takeTurns = false }
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.circle.fill").font(.title2).foregroundStyle(.orange).frame(width: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Anyone (up for grabs)")
                                Text("First to do it gets the points.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: draft.upForGrabs ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.upForGrabs ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.upForGrabs ? .isSelected : [])
                    ForEach(household.kids) { kid in
                        Button { toggle(kid) } label: {
                            HStack {
                                Avatar(member: kid, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(kid.displayName)
                                    if let load = workload(kid) {
                                        Text(load).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selected.contains(kid) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(kid) ? .isSelected : [])
                    }
                    if !draft.upForGrabs && (selected.count > 1 || draft.takeTurns) {
                        Toggle("Take turns", isOn: $draft.takeTurns)
                            .onChange(of: draft.takeTurns) { _, on in
                                // An edited chore without turns belongs to one kid again: whoever has it now.
                                if !on, isEditing, let current = chore?.assignee { selected = [current] }
                            }
                        Text(turnsHint).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Schedule") {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker(draft.dueWithinWeek ? "Week of" : "Due", selection: $due, displayedComponents: .date)
                        Toggle("Any day that week", isOn: $draft.dueWithinWeek)
                        if !draft.dueWithinWeek {
                            Toggle("By a certain time", isOn: $hasTime)
                        }
                        if hasTime && !draft.dueWithinWeek {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                    Picker("Time of day", selection: $draft.timeOfDay) {
                        Text("Anytime").tag(TimeOfDay?.none)
                        ForEach(TimeOfDay.allCases) { Label($0.title, systemImage: $0.icon).tag(TimeOfDay?.some($0)) }
                    }
                    Picker("Repeat", selection: $draft.recurrence.kind) {
                        ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.recurrence.kind == .weekly {
                        WeekdayPicker(weekdays: Binding(
                            get: { draft.recurrence.weekdays },
                            set: { draft.recurrence.weekdays = $0 }))
                    }
                }
                .onChange(of: draft.recurrence.kind) { _, kind in
                    if kind != .none { hasDue = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Chore" : "New Chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Assign") { save() }
                        .disabled(draft.title.trimmed.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 640)
    }

    private func toggle(_ kid: Member) {
        draft.upForGrabs = false
        if isEditing && !draft.takeTurns {
            selected = [kid]
        } else if selected.contains(kid) {
            selected.remove(kid)
        } else {
            selected.insert(kid)
        }
    }

    private func save() {
        draft.dueDate = hasDue ? due : nil
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.dueTime = hasDue && hasTime ? (clock.hour ?? 0) * 60 + (clock.minute ?? 0) : nil
        if selected.count < 2 { draft.takeTurns = false }
        let ordered = draft.upForGrabs ? [] : household.kids.filter { selected.contains($0) }
        do {
            if let chore {
                try service.updateChore(chore, with: draft, assignees: ordered, by: me)
            } else {
                try service.createChores(draft, assignees: ordered, in: household, by: me)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Theme.accent : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A row of chore pictures, with "none" first.
struct ChoreEmojiPicker: View {
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil)
                ForEach(Theme.choreEmojis, id: \.self) { chip($0) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ emoji: String?) -> some View {
        let on = selection == emoji
        return Button { selection = emoji } label: {
            Group {
                if let emoji { Text(emoji).font(.title2) } else { Image(systemName: "nosign").foregroundStyle(.secondary) }
            }
            .frame(width: 44, height: 44)
            .background(on ? Theme.accent.opacity(0.25) : Color.secondary.opacity(0.12), in: Circle())
            .overlay(Circle().stroke(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(emoji ?? String(localized: "No picture"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Lets a parent edit a chore wherever it appears: long-press (or right-click) it, or swipe on a list row.
private struct ChoreEditing: ViewModifier {
    @ObservedObject var chore: Chore
    let household: Household
    let me: Member
    @State private var editing = false

    private var canEdit: Bool { me.isParent && chore.status == .todo }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if canEdit { Button("Edit", systemImage: "pencil") { editing = true } }
            }
            .swipeActions(edge: .trailing) {
                if canEdit { Button("Edit", systemImage: "pencil") { editing = true }.tint(Theme.accent) }
            }
            .sheet(isPresented: $editing) { ChoreEditorView(household: household, me: me, chore: chore) }
    }
}

extension View {
    func choreEditing(_ chore: Chore, household: Household, me: Member) -> some View {
        modifier(ChoreEditing(chore: chore, household: household, me: me))
    }
}
