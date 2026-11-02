import SwiftUI

/// Starts a project from a preset like "Guests are coming", or from scratch.
struct ProjectEditorView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HouseholdService.ProjectDraft()
    @State private var chosen: String?
    @State private var kids: Set<Member> = []
    @State private var newTask = ""
    @State private var error: String?

    private var defaultDeadline: Date {
        Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What's the project?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ProjectLibrary.presets) { preset in
                                presetChip(preset.emoji, preset.title, on: chosen == preset.id) { choose(preset) }
                            }
                            presetChip("✏️", String(localized: "From scratch"), on: chosen == "scratch") { chooseScratch() }
                        }
                        .padding(.vertical, 4)
                    }
                    if chosen != nil {
                        TextField("Project name", text: $draft.title)
                    }
                }

                if chosen != nil {
                    Section {
                        DatePicker("Done by", selection: $draft.dueDate, in: Date()..., displayedComponents: .date)
                        Toggle("Comes first", isOn: $draft.pausesRegular)
                    } footer: {
                        Text(draft.pausesRegular
                             ? "Regular chores wait until the project is done or the date passes: no overdue chores, no reminders."
                             : "Regular chores carry on as usual alongside the project.")
                    }

                    Section {
                        Button { kids = [] } label: {
                            checkRow(String(localized: "Everyone pitches in"), detail: String(localized: "Every chore is up for grabs."),
                                     on: kids.isEmpty)
                        }
                        .buttonStyle(.plain)
                        ForEach(household.kids) { kid in
                            Button { if kids.contains(kid) { kids.remove(kid) } else { kids.insert(kid) } } label: {
                                checkRow("\(kid.displayEmoji) \(kid.displayName)", detail: nil, on: kids.contains(kid))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Who")
                    } footer: {
                        Text(kids.isEmpty ? "" : String(localized: "Chores are shared out so everyone gets about the same amount of time."))
                    }

                    ForEach(Array(draft.phases.enumerated()), id: \.offset) { index, phase in
                        Section(draft.phases.count > 1 ? String(localized: "Step \(index + 1): \(phase)") : phase) {
                            ForEach(draft.tasks.filter { $0.phase == index }) { task in
                                HStack {
                                    Text(task.emoji)
                                    Text(task.title)
                                    Spacer()
                                    Text(Effort.label(minutes: task.minutes, difficulty: task.difficulty) ?? "")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .swipeActions { Button("Remove", role: .destructive) { remove(task) } }
                            }
                        }
                    }
                    Section {
                        HStack {
                            TextField("Add a chore", text: $newTask)
                                .onSubmit(addTask)
                            Button("Add", action: addTask).disabled(newTask.trimmed.isEmpty)
                        }
                    } footer: {
                        Text("Swipe a chore to remove it. Steps go in order: tidy before you clean.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.disabled(chosen == nil || draft.tasks.isEmpty)
                }
            }
            .errorAlert($error)
        }
        .sheetFrame(height: 680)
    }

    private func presetChip(_ emoji: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(emoji).font(.largeTitle)
                Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: 96, height: 96)
            .background(on ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func checkRow(_ title: String, detail: String?, on: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func choose(_ preset: ProjectLibrary.Preset) {
        chosen = preset.id
        draft = HouseholdService.ProjectDraft(preset: preset, dueDate: defaultDeadline)
    }

    private func chooseScratch() {
        chosen = "scratch"
        draft = HouseholdService.ProjectDraft()
        draft.dueDate = defaultDeadline
        draft.phases = [String(localized: "To do")]
    }

    private func addTask() {
        let title = newTask.trimmed
        guard !title.isEmpty else { return }
        draft.tasks.append(ProjectLibrary.Task(title: title, emoji: "✅", minutes: 15, difficulty: .medium, points: 5,
                                               phase: max(0, draft.phases.count - 1)))
        newTask = ""
    }

    private func remove(_ task: ProjectLibrary.Task) {
        draft.tasks.removeAll { $0 == task }
    }

    private func start() {
        do {
            try service.startProject(draft, sharedWith: household.kids.filter { kids.contains($0) }, in: household, by: me)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A project at the top of the chore list: what it is, when it's due, how far along, and its chores by step.
struct ProjectSection: View {
    @ObservedObject var project: Project
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @State private var confirmingEnd = false

    /// For a kid: their own project chores and any still up for grabs. For a parent: all of them.
    private var chores: [Chore] {
        project.chores.filter { me.isParent || $0.assignee == me || $0.isUnclaimed }
    }

    var body: some View {
        let chores = chores
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(project.displayEmoji).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayTitle).font(.headline)
                        if let due = project.dueDate {
                            Text("Done by \(dueText(due))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(project.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.title3.bold()).foregroundStyle(Theme.accent)
                }
                ProgressView(value: project.progress).tint(Theme.accent)
                if project.pausesRegular {
                    Label("Regular chores wait until this is done.", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contextMenu {
                if me.isParent {
                    Button("End project", systemImage: "xmark.circle", role: .destructive) { confirmingEnd = true }
                }
            }
            ForEach(Array(Set(chores.map { Int($0.phase) })).sorted(), id: \.self) { phase in
                let laterStep = (project.currentPhase ?? phase) < phase
                Text(project.phaseNames.count > 1
                     ? String(localized: "Step \(phase + 1): \(project.phaseName(phase))") : project.phaseName(phase))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(chores.filter { Int($0.phase) == phase }) { chore in
                    NavigationLink(value: chore) {
                        ChoreRow(chore: chore, showAssignee: me.isParent)
                    }
                    .choreEditing(chore, household: household, me: me)
                    // Later steps are best left until the earlier ones are done.
                    .opacity(laterStep && chore.status == .todo ? 0.55 : 1)
                }
            }
        } header: {
            Label("Project", systemImage: "hammer")
        }
        .confirmationDialog(String(localized: "End \(project.displayTitle)?"), isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End project", role: .destructive) {
                try? service.endProject(project, by: me)
            }
        } message: {
            Text("Unfinished project chores are removed. Points already earned stay.")
        }
    }
}
