import SwiftUI
import CoreData

/// Parents' inbox: chores to confirm and rewards to approve.
struct ReviewView: View {
    let household: Household
    let me: Member
    @EnvironmentObject private var service: HouseholdService
    @FetchRequest private var chores: FetchedResults<Chore>
    @FetchRequest private var requests: FetchedResults<Redemption>
    @State private var error: String?
    /// A short cheer after each approval, and a count that buzzes the phone each time.
    @State private var toast: String?
    @State private var approvals = 0
    @State private var confirmingAll = false

    init(household: Household, me: Member) {
        self.household = household
        self.me = me
        _chores = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Chore.completedAt, ascending: true)],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, ChoreStatus.pendingReview.rawValue),
            animation: .default)
        _requests = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Redemption.requestedAt, ascending: true)],
            predicate: NSPredicate(format: "household == %@ AND statusRaw == %@", household, RedemptionStatus.requested.rawValue),
            animation: .default)
    }

    var body: some View {
        List {
            if !chores.isEmpty {
                Section("Chores to confirm") {
                    ForEach(chores) { chore in
                        HStack {
                            NavigationLink(value: chore) {
                                ChoreRow(chore: chore, showAssignee: true)
                            }
                            Button { approve(chore) } label: {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.green, in: Circle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(localized: "Approve \(chore.displayTitle)"))
                        }
                        .swipeActions(edge: .leading) {
                            Button("Approve") { approve(chore) }.tint(.green)
                        }
                        .contextMenu {
                            Button("Approve (\(chore.points) pts)", systemImage: "checkmark.seal") { approve(chore) }
                        }
                    }
                }
            }
            if !requests.isEmpty {
                Section("Reward requests") {
                    ForEach(requests) { request in
                        RedemptionRow(request: request, me: me, onError: { error = $0 }, onApproved: {
                            approvals += 1
                            show(String(localized: "\(request.displayEmoji) \(request.displayTitle) for \(request.member?.displayName ?? "")!"))
                        })
                    }
                }
            }
        }
        .overlay {
            if chores.isEmpty && requests.isEmpty {
                GoatEmptyView(
                    title: "All caught up",
                    mood: .cheer,
                    description: Text("Finished chores and reward requests show up here for you to confirm."))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 10) {
                    Goat(mood: .cheer, size: 44)
                    Text(toast).font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { self.toast = nil }
                }
            }
        }
        .sensoryFeedback(.success, trigger: approvals)
        .toolbar {
            if chores.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Approve all") { confirmingAll = true }
                }
            }
        }
        .confirmationDialog(String(localized: "Approve every chore here?"), isPresented: $confirmingAll, titleVisibility: .visible) {
            Button("Approve all") { approveAll() }
        }
        .navigationTitle("Review")
        .navigationDestination(for: Chore.self) { ChoreDetailView(chore: $0, me: me) }
        .errorAlert($error)
    }

    private func approve(_ chore: Chore) {
        let name = chore.assignee?.displayName ?? ""
        do {
            try withAnimation { try service.approve(chore, by: me) }
            approvals += 1
            show(chore.awardedPoints > 0 ? String(localized: "+\(Int(chore.awardedPoints)) for \(name)!")
                                         : String(localized: "Nice work, \(name)!"))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func approveAll() {
        let all = Array(chores)
        do {
            try withAnimation { for chore in all { try service.approve(chore, by: me) } }
            approvals += 1
            show(String(localized: "All done. Nice work, everyone!"))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func show(_ message: String) {
        withAnimation(.spring) { toast = message }
    }
}

struct RedemptionRow: View {
    @ObservedObject var request: Redemption
    let me: Member
    let onError: (String) -> Void
    var onApproved: () -> Void = {}
    @EnvironmentObject private var service: HouseholdService

    var body: some View {
        HStack(spacing: 12) {
            if let kid = request.member { Avatar(member: kid, size: 38) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(request.displayEmoji) \(request.displayTitle)").font(.headline)
                Text("\(request.member?.displayName ?? String(localized: "Someone")) · \(request.cost) pts")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            // Round buttons, like the chores above, so they never wrap however long the reward's name.
            Button { decide(false) } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
                    .background(Color.red.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Deny")
            Button { decide(true) } label: {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.green, in: Circle())
            }
            .accessibilityLabel("Approve")
        }
        .buttonStyle(.borderless)
    }

    private func decide(_ approve: Bool) {
        do {
            try withAnimation { try service.decide(request, approve: approve, by: me) }
            if approve { onApproved() }
        } catch {
            onError(error.localizedDescription)
        }
    }
}
