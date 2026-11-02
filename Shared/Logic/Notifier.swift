import Foundation
import UserNotifications

/// Local notifications driven by what the synced data says.
///
/// CloudKit delivers a silent push when another household member changes
/// something; Core Data imports it, and `AppEnvironment` calls `sync` afterwards.
/// We then turn anything new that concerns this person into a banner, and keep
/// due-date reminders scheduled for their open chores.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    /// Runs a button tapped on a notification. Set by `AppEnvironment`, which knows who is signed in.
    var onAction: (@MainActor (Action, UUID, String?) async -> Void)?

    func start() {
        center.delegate = self
        center.setNotificationCategories(Self.categories)
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let (action, id) = Self.parse(actionIdentifier: response.actionIdentifier,
                                            userInfo: response.notification.request.content.userInfo) else { return }
        let note = (response as? UNTextInputNotificationResponse)?.userText
        // Finish the work before returning: the system may suspend the app as soon as this does.
        await onAction?(action, id, note)
    }

    /// Which button was tapped and on what. Plain taps (which just open the app) return nil.
    nonisolated static func parse(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> (Action, UUID)? {
        guard let action = Action(rawValue: actionIdentifier),
              let idString = userInfo[objectIDKey] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        return (action, id)
    }

    // MARK: Actions

    /// Buttons a parent can use straight from a notification, without opening the app.
    enum Action: String, CaseIterable {
        case approveChore = "approve-chore"
        case sendBack = "send-back"
        case approveReward = "approve-reward"
        case denyReward = "deny-reward"
    }

    enum Category: String {
        case choreReview = "chore-review"
        case rewardRequest = "reward-request"
    }

    nonisolated static let objectIDKey = "objectID"

    /// Every action needs the device unlocked, so a kid holding a parent's phone can't approve.
    static var categories: Set<UNNotificationCategory> {
        let locked: UNNotificationActionOptions = [.authenticationRequired]
        return [
            UNNotificationCategory(identifier: Category.choreReview.rawValue, actions: [
                UNNotificationAction(identifier: Action.approveChore.rawValue, title: String(localized: "Approve"), options: locked),
                UNTextInputNotificationAction(identifier: Action.sendBack.rawValue, title: String(localized: "Send back"), options: locked,
                                              textInputButtonTitle: String(localized: "Send"),
                                              textInputPlaceholder: String(localized: "What needs another look?")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.rewardRequest.rawValue, actions: [
                UNNotificationAction(identifier: Action.approveReward.rawValue, title: String(localized: "Approve"), options: locked),
                UNNotificationAction(identifier: Action.denyReward.rawValue, title: String(localized: "Deny"), options: locked.union(.destructive)),
            ], intentIdentifiers: []),
        ]
    }

    /// Carries out a notification button through the same rules as the app's own buttons.
    static func perform(_ action: Action, on id: UUID, note: String?, household: Household, me: Member,
                        service: HouseholdService) throws {
        switch action {
        case .approveChore, .sendBack:
            guard let chore = ((household.chores as? Set<Chore>) ?? []).first(where: { $0.id == id }) else {
                throw ServiceError.invalid(String(localized: "That chore is gone."))
            }
            if action == .approveChore {
                try service.approve(chore, by: me)
            } else {
                try service.reject(chore, by: me, note: note ?? "")
            }
        case .approveReward, .denyReward:
            guard let request = ((household.redemptions as? Set<Redemption>) ?? []).first(where: { $0.id == id }) else {
                throw ServiceError.invalid(String(localized: "That request is gone."))
            }
            try service.decide(request, approve: action == .approveReward, by: me)
        }
    }

    /// Carries out the button, and tells the parent if it couldn't be done (say, the other parent got there first).
    func handle(_ action: Action, on id: UUID, note: String?, household: Household, me: Member, service: HouseholdService) {
        do {
            try Self.perform(action, on: id, note: note, household: household, me: me, service: service)
        } catch {
            reportFailure(error.localizedDescription)
        }
    }

    private func reportFailure(_ message: String) {
        let failure = Event(key: "failed-\(UUID().uuidString)", title: String(localized: "Couldn't do that"), body: message)
        center.add(UNNotificationRequest(identifier: failure.key, content: failure.content, trigger: nil))
    }

    struct Event: Equatable {
        let key: String
        let title: String
        let body: String
        var category: Category?
        var objectID: UUID?

        /// The banner, with its buttons when it has any.
        var content: UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let category, let objectID {
                content.categoryIdentifier = category.rawValue
                content.userInfo = [Notifier.objectIDKey: objectID.uuidString]
            }
            return content
        }
    }

    func sync(household: Household, me: Member) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            deliverNewEvents(household: household, me: me)
            await scheduleDueReminders(household: household, me: me)
            scheduleWeeklyRecap(for: me)
        }
    }

    func events(household: Household, me: Member) -> [Event] {
        let chores = (household.chores as? Set<Chore>) ?? []
        let redemptions = (household.redemptions as? Set<Redemption>) ?? []
        var result: [Event] = []

        if me.isParent {
            for chore in chores where chore.status == .pendingReview {
                let when = chore.completedAt?.timeIntervalSince1970 ?? 0
                result.append(Event(
                    key: "review-\(chore.id?.uuidString ?? "")-\(when)",
                    title: String(localized: "\(chore.assignee?.displayName ?? "Someone") finished a chore"),
                    body: String(localized: "\(chore.displayTitle) is ready for you to check. Worth \(chore.points) points."),
                    category: .choreReview, objectID: chore.id))
            }
            for request in redemptions where request.status == .requested {
                result.append(Event(
                    key: "redeem-\(request.id?.uuidString ?? "")",
                    title: String(localized: "\(request.member?.displayName ?? "Someone") wants a reward"),
                    body: String(localized: "\(request.displayEmoji) \(request.displayTitle) · \(request.cost) pts"),
                    category: .rewardRequest, objectID: request.id))
            }
        } else {
            for chore in chores where chore.isUnclaimed && chore.status == .todo {
                result.append(Event(
                    key: "grabs-\(chore.id?.uuidString ?? "")",
                    title: String(localized: "Up for grabs: \(chore.displayTitle)"),
                    body: String(localized: "First to do it gets \(chore.points) points.")))
            }
            for chore in chores where chore.assignee?.id == me.id && chore.status == .todo {
                guard let nudged = chore.nudgedAt else { continue }
                result.append(Event(
                    key: "nudge-\(chore.id?.uuidString ?? "")-\(nudged.timeIntervalSince1970)",
                    title: String(localized: "Reminder from \(chore.nudgedByName ?? String(localized: "a parent"))"),
                    body: [chore.emoji, chore.displayTitle].compactMap { $0 }.joined(separator: " ")))
            }
            for chore in chores where chore.assignee?.id == me.id {
                switch chore.status {
                case .todo where chore.wasSentBack:
                    let when = chore.reviewedAt?.timeIntervalSince1970 ?? 0
                    result.append(Event(
                        key: "sentback-\(chore.id?.uuidString ?? "")-\(when)",
                        title: String(localized: "\(chore.displayTitle) needs another look"),
                        body: chore.reviewNote ?? ""))
                case .todo:
                    result.append(Event(
                        key: "assigned-\(chore.id?.uuidString ?? "")",
                        title: String(localized: "New chore: \(chore.displayTitle)"),
                        body: String(localized: "Worth \(chore.points) points.")))
                case .approved:
                    guard let reviewed = chore.reviewedAt, reviewed > Date().addingTimeInterval(-86_400) else { continue }
                    result.append(Event(
                        key: "approved-\(chore.id?.uuidString ?? "")",
                        title: String(localized: "You earned \(chore.awardedPoints) points!"),
                        body: String(localized: "\(chore.displayTitle) was approved.")))
                case .pendingReview:
                    break
                }
            }
            for request in redemptions where request.member?.id == me.id && request.status != .requested {
                result.append(Event(
                    key: "decided-\(request.id?.uuidString ?? "")",
                    title: request.status == .approved ? String(localized: "Reward approved!") : String(localized: "Reward not approved"),
                    body: String(localized: "\(request.displayEmoji) \(request.displayTitle)")))
            }
            for entry in me.entryList where entry.kind == .bonus {
                guard let date = entry.date, date > Date().addingTimeInterval(-86_400) else { continue }
                result.append(Event(
                    key: "bonus-\(entry.id?.uuidString ?? "")",
                    title: String(localized: "Bonus! +\(entry.amount) points"),
                    body: entry.reason ?? String(localized: "From a parent.")))
            }
            for entry in me.entryList where entry.kind == .payout {
                guard let date = entry.date, date > Date().addingTimeInterval(-86_400) else { continue }
                result.append(Event(
                    key: "payout-\(entry.id?.uuidString ?? "")",
                    title: entry.reason ?? String(localized: "You got paid"),
                    body: String(localized: "For \(-entry.amount) points.")))
            }
        }
        return result
    }

    /// The first sync just records what already exists so installing doesn't flood the user.
    static func eventsToDeliver(current: [Event], seen: Set<String>, isFirstRun: Bool) -> [Event] {
        isFirstRun ? [] : current.filter { !seen.contains($0.key) }
    }

    private func deliverNewEvents(household: Household, me: Member) {
        let seenKey = "notified.\(me.id?.uuidString ?? "")"
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let current = events(household: household, me: me)
        let isFirstRun = defaults.stringArray(forKey: seenKey) == nil

        for event in Notifier.eventsToDeliver(current: current, seen: seen, isFirstRun: isFirstRun) {
            center.add(UNNotificationRequest(identifier: event.key, content: event.content, trigger: nil))
        }
        seen.formUnion(current.map(\.key))
        defaults.set(Array(seen), forKey: seenKey)

        if me.isParent {
            let pending = current.count
            Task { try? await center.setBadgeCount(pending) }
        } else {
            Task { try? await center.setBadgeCount(0) }
        }
    }

    struct Reminder: Equatable {
        let id: String
        let title: String
        let body: String
        let fireAt: DateComponents
    }

    /// A 9am reminder on the due date for each of this kid's open chores, skipping
    /// any whose reminder time has already passed. Parents get none.
    static func dueReminders(household: Household, me: Member, now: Date = Date(),
                             calendar: Calendar = .current) -> [Reminder] {
        guard !me.isParent else { return [] }
        let chores = ((household.chores as? Set<Chore>) ?? []).filter {
            $0.assignee?.id == me.id && $0.status == .todo
        }
        return chores.compactMap { chore in
            guard let due = chore.dueDate, let id = chore.id else { return nil }
            if household.isPaused(on: due, calendar: calendar) || chore.extraCredit || chore.isMenuOption
                || chore.isOnHold(now: now, calendar: calendar) {
                return nil
            }
            if let dueAt = chore.dueAt(calendar: calendar), chore.dueTime != nil {
                // An hour's warning, but never before the start of the day it's due.
                let fireDate = max(dueAt.addingTimeInterval(-3600), calendar.startOfDay(for: due))
                guard fireDate > now else { return nil }
                return Reminder(id: "due-\(id.uuidString)", title: String(localized: "Due soon: \(chore.displayTitle)"),
                                body: String(localized: "By \(dueAt.formatted(date: .omitted, time: .shortened)). Worth \(chore.points) points."),
                                fireAt: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate))
            }
            var parts = calendar.dateComponents([.year, .month, .day], from: due)
            parts.hour = 9
            guard let fireDate = calendar.date(from: parts), fireDate > now else { return nil }
            return Reminder(id: "due-\(id.uuidString)", title: String(localized: "Due today: \(chore.displayTitle)"),
                            body: String(localized: "Worth \(chore.points) points."), fireAt: parts)
        }
    }

    static let weeklyRecapID = "weekly-recap"

    /// Parents get a Sunday-evening nudge to look at the week; kids don't.
    private func scheduleWeeklyRecap(for me: Member) {
        guard me.isParent else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyRecapID])
            return
        }
        let recap = Event(key: Self.weeklyRecapID, title: String(localized: "How did the week go?"),
                          body: String(localized: "See everyone's points and chores in the weekly recap.")).content
        let trigger = UNCalendarNotificationTrigger(dateMatching: WeeklyRecap.reminderTime, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.weeklyRecapID, content: recap, trigger: trigger))
    }

    private func scheduleDueReminders(household: Household, me: Member) async {
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("due-") }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        for reminder in Notifier.dueReminders(household: household, me: me) {
            let content = Event(key: reminder.id, title: reminder.title, body: reminder.body).content
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireAt, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
