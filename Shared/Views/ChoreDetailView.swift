import SwiftUI
import PhotosUI

struct ChoreDetailView: View {
    @ObservedObject var chore: Chore
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @Environment(\.dismiss) private var dismiss

    @State private var showingComplete = false
    @State private var showingTimer = false
    @State private var showingEdit = false
    @State private var showingSendBack = false
    @State private var confirmingDelete = false
    @State private var awardPoints = 0
    @State private var sendBackNote = ""
    @State private var error: String?

    private var isAssignee: Bool { chore.assignee?.id == me.id }

    /// The once-a-day pass is offered for a chore due today, if today's pass is still unused.
    private var canUseResetPass: Bool {
        let calendar = Calendar.current
        guard let due = chore.dueDate, due < (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date())
        else { return false }
        return !(me.resetUsedOn.map { calendar.isDateInToday($0) } ?? false)
    }

    var body: some View {
        Form {
            starsSection
            detailsSection
            if chore.isRoutine { stepsSection }

            if chore.wasSentBack {
                Section("Sent back") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chore.reviewNote ?? "")
                            if let name = chore.reviewedByName {
                                Text("— \(name)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.orange)
                    }
                }
            }

            if chore.status == .pendingReview { turnedInSection }

            if chore.status == .approved {
                Section("Approved") {
                    Label("\(chore.awardedPoints) points awarded", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    if let date = chore.reviewedAt {
                        // No reviewer means the chore approves itself.
                        Text("\(chore.reviewedByName ?? String(localized: "Automatically")) · \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            actionsSection
        }
        .formStyle(.grouped)
        .navigationTitle([chore.emoji, chore.displayTitle].compactMap { $0 }.joined(separator: " "))
        .toolbar {
            if me.isParent && chore.status == .todo {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit", systemImage: "pencil") { showingEdit = true }
                        if chore.status == .todo, chore.assignee != nil {
                            Button("Send a reminder", systemImage: "bell.badge") { perform { try service.nudge(chore, by: me) } }
                        }
                        if chore.takesTurns, chore.status == .todo {
                            Button("Skip this turn", systemImage: "forward") { perform { try service.skipTurn(chore, by: me) } }
                        }
                        if chore.upForGrabs, chore.status == .todo, chore.assignee != nil {
                            Button("Put back up for grabs", systemImage: "hand.raised") { perform { try service.release(chore, by: me) } }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        }
        .onAppear { awardPoints = Int(chore.points) }
        .sheet(isPresented: $showingTimer) {
            ChoreTimerView(title: chore.displayTitle, emoji: chore.emoji, minutes: chore.minutes ?? 10)
        }
        .sheet(isPresented: $showingComplete) {
            CompleteChoreSheet(chore: chore) { note, photo in
                perform { try service.markComplete(chore, by: me, note: note, photo: photo) }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let household = chore.household {
                ChoreEditorView(household: household, me: me, chore: chore)
            }
        }
        .alert("Send back to \(chore.assignee?.displayName ?? "them")?", isPresented: $showingSendBack) {
            TextField("What needs another look?", text: $sendBackNote)
            Button("Send Back") {
                perform { try service.reject(chore, by: me, note: sendBackNote) }
                sendBackNote = ""
            }
            Button("Cancel", role: .cancel) { sendBackNote = "" }
        } message: {
            Text("No points are awarded. They'll see your note and can try again.")
        }
        .confirmationDialog("Delete this chore?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Chore", role: .destructive) {
                perform {
                    try service.deleteChore(chore, by: me)
                    dismiss()
                }
            }
        }
        .errorAlert($error)
    }

    /// The chore's "character card": what it asks of you, how it helps, and how to do it well.
    @ViewBuilder
    private var starsSection: some View {
        let stars = Effort.stars(minutes: chore.minutes, difficulty: chore.difficulty, skill: chore.skill)
        let level = ChoreLevel.of(chore)
        if !stars.isEmpty || chore.whyItHelps != nil || chore.stretch || level != nil {
            Section {
                if !stars.isEmpty {
                    StarRow(title: String(localized: "Time"), icon: "stopwatch", stars: stars.time)
                    StarRow(title: String(localized: "Difficulty"), icon: "dumbbell", stars: stars.difficulty)
                    StarRow(title: String(localized: "Problem-solving"), icon: "puzzlepiece", stars: stars.thinking)
                    if chore.household?.has(.energy) == true {
                        LabeledContent {
                            Text(String(repeating: "🥄", count: chore.spoons))
                        } label: {
                            Label("Energy", systemImage: "battery.50percent")
                        }
                        .accessibilityLabel("Energy: \(chore.spoons) spoons")
                    }
                }
                if let level {
                    Label {
                        Text(level.title) + Text(verbatim: " · ") + Text("Done \(ChoreLevel.timesDone(chore)) times")
                    } icon: { Image(systemName: level.icon) }
                    .foregroundStyle(.secondary)
                }
                if chore.stretch {
                    Label("Stretch chore: a step up. You've got this!", systemImage: "arrow.up.forward.circle")
                        .foregroundStyle(.purple)
                }
                if chore.extraCredit {
                    Label("Extra credit: optional, and it earns points", systemImage: "plus.circle")
                        .foregroundStyle(.green)
                }
            }
        }
        if let helps = chore.whyItHelps {
            Section {
                Label(helps, systemImage: "heart.fill").foregroundStyle(Color.primary)
            } header: {
                Text("How it helps the family")
            }
        }
        if let tips = chore.tips {
            Section {
                Label(tips, systemImage: "lightbulb.fill")
            } header: {
                Text("Tips")
            }
        }
    }

    /// The kid ticks steps off; everyone else sees how far they've got.
    private var stepsSection: some View {
        let canTick = isAssignee && !me.isParent && chore.status == .todo
        return Section("Steps") {
            ForEach(Array(chore.steps.enumerated()), id: \.offset) { index, step in
                let done = chore.doneSteps.contains(index) || chore.status != .todo
                Button {
                    do { try service.toggleStep(index, of: chore, by: me) } catch { self.error = error.localizedDescription }
                } label: {
                    HStack {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Color.green : Color.secondary)
                            .font(.title3)
                        Text(step).strikethrough(done && canTick).foregroundStyle(Color.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canTick)
                .accessibilityAddTraits(done ? .isSelected : [])
            }
        }
    }

    private var detailsSection: some View {
        Section {
            if let notes = chore.notes, !notes.isEmpty {
                Text(notes)
            }
            LabeledContent("Worth") { PointsBadge(points: Int(chore.points)) }
            if let effort = chore.effortLabel {
                LabeledContent("Effort", value: effort)
            }
            if let assignee = chore.assignee, !chore.upForGrabs {
                LabeledContent("Assigned to") {
                    HStack(spacing: 6) { Text(assignee.displayEmoji); Text(assignee.displayName) }
                }
            }
            if let due = dueText(for: chore) {
                LabeledContent("Due") {
                    Text(due).foregroundStyle(chore.isOverdue ? Color.red : Color.primary)
                }
            }
            if chore.recurrence.isRepeating {
                LabeledContent("Repeats", value: chore.recurrence.summary())
            }
            if chore.autoApprove {
                LabeledContent("Approval", value: String(localized: "Automatic"))
            }
            if chore.upForGrabs {
                LabeledContent("Up for grabs", value: chore.assignee.map { String(localized: "Taken by \($0.displayName)") }
                               ?? String(localized: "First to do it gets the points"))
            }
            if let time = chore.timeOfDay {
                LabeledContent("When", value: time.title)
            }
            if chore.status == .todo, let nudged = chore.nudgedAt {
                LabeledContent("Reminder sent", value: nudged.formatted(.relative(presentation: .named)))
            }
            if chore.photoRequired {
                LabeledContent("Photo", value: String(localized: "Needed to turn in"))
            }
            if chore.takesTurns {
                LabeledContent("Taking turns", value: chore.rotation.map(\.displayName).joined(separator: " → "))
                if chore.status != .approved, let next = chore.nextAssignee {
                    LabeledContent("Next time", value: next.displayName)
                }
            }
        }
    }

    private var turnedInSection: some View {
        Section("Turned in") {
            if let date = chore.completedAt {
                Text("\(chore.assignee?.displayName ?? String(localized: "They")) finished this \(date.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
            if let note = chore.completionNote { Text("“\(note)”") }
            if let photo = chore.photo {
                PhotoView(data: photo)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if chore.status == .todo && ((isAssignee && me.isParent) || ((isAssignee || chore.isUnclaimed) && !me.isParent)) {
            Section {
                if chore.isUnclaimed {
                    Button { perform { try service.claim(chore, by: me) } } label: {
                        Label("I'll do it", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                if chore.minutes != nil {
                    Button { showingTimer = true } label: {
                        Label("Start a timer", systemImage: "timer").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                Button {
                    // A grown-up's own chore is just done; no note or photo for anyone to check.
                    if me.isParent { perform { try service.markComplete(chore, by: me, note: nil, photo: nil) } } else { showingComplete = true }
                } label: {
                    Label("I'm done!", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!chore.allStepsDone)
                if chore.upForGrabs && isAssignee {
                    Button("Let someone else do it") { perform { try service.release(chore, by: me) } }
                        .frame(maxWidth: .infinity)
                }
                if !me.isParent && chore.menuPicked && ChoiceMenu.options(like: chore).contains(where: \.isMenuOption) {
                    Button("Change my mind") { perform { try service.unpick(chore, by: me) } }
                        .frame(maxWidth: .infinity)
                }
                if !me.isParent && isAssignee && canUseResetPass && chore.household?.has(.energy) == true {
                    Button("Not today: use my reset pass") { perform { try service.useResetPass(on: chore, by: me) } }
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(me.isParent
                     ? "The kids will see you got it done."
                     : !chore.allStepsDone
                     ? "Tick off every step first."
                     : chore.autoApprove
                     ? "You'll get your points right away."
                     : "A parent will check it before you get your points.")
            }
        }

        if chore.status == .pendingReview && isAssignee {
            Section {
                Label("Waiting for a parent to approve", systemImage: "hourglass")
                Button("Take it back") { perform { try service.withdraw(chore, by: me) } }
            }
        }

        if chore.status == .pendingReview && me.isParent {
            Section("Review") {
                Stepper(value: $awardPoints, in: 0...10_000) {
                    Text("Award \(awardPoints) points")
                }
                if awardPoints != Int(chore.points) {
                    Text("Usually \(chore.points). Adjust for partial or bonus credit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { perform { try service.approve(chore, by: me, points: awardPoints) } } label: {
                    Label("Approve & Award Points", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button(role: .destructive) { showingSendBack = true } label: {
                    Label("Send Back…", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }
}

/// Asks for an optional note and photo before turning a chore in.
struct CompleteChoreSheet: View {
    let chore: Chore
    let onSubmit: (String?, Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var loadingPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(chore.autoApprove
                         ? "You'll get your points for “\(chore.displayTitle)” right away."
                         : "A parent will check “\(chore.displayTitle)” before you get your points.")
                        .foregroundStyle(.secondary)
                }
                Section("Add a note (optional)") {
                    TextField("Anything they should know?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section(chore.photoRequired ? "Show your work" : "Show your work (optional)") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Add a photo" : "Choose a different photo", systemImage: "photo")
                    }
                    if loadingPhoto { ProgressView() }
                    if let photo {
                        PhotoView(data: photo).frame(maxHeight: 220)
                        Button("Remove photo", role: .destructive) { self.photo = nil; pickerItem = nil }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Turn in chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Turn In") {
                        onSubmit(note, photo)
                        dismiss()
                    }
                    .disabled(loadingPhoto || (chore.photoRequired && photo == nil))
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                loadingPhoto = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = ImageProcessing.jpegData(from: data)
                    }
                    loadingPhoto = false
                }
            }
        }
        .sheetFrame(height: 520)
    }
}

/// One stat on a chore's card, out of five stars.
private struct StarRow: View {
    let title: String
    let icon: String
    let stars: Int?

    var body: some View {
        if let stars {
            LabeledContent {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= stars ? "star.fill" : "star")
                            .foregroundStyle(i <= stars ? Color.orange : Color.secondary.opacity(0.4))
                    }
                }
                .font(.subheadline)
            } label: {
                Label(title, systemImage: icon)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(stars) of 5 stars")
        }
    }
}
