import Foundation
import Observation
import UserNotifications
import SwiftBoardKit

@MainActor
@Observable
final class DeadlineNotificationCenter {
    static let enabledKey = "deadlineNotificationsEnabled"
    static let authorizationKey = "deadlineNotificationsAuthorization"

    private static let identifierPrefix = "deadline."
    private let center = UNUserNotificationCenter.current()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    init() {
        authorizationStatus = Self.cachedAuthorization
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        Self.cachedAuthorization = settings.authorizationStatus
        if settings.authorizationStatus == .denied {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
        }
    }

    /// Returns the effective enabled state after the system permission prompt.
    func setEnabled(_ enabled: Bool, deadlines: [Deadline]) async -> Bool {
        if !enabled {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            await removeScheduled()
            return false
        }

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let updated = await center.notificationSettings()
            authorizationStatus = updated.authorizationStatus
        }
        Self.cachedAuthorization = authorizationStatus

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }

        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await sync(deadlines: deadlines)
        return true
    }

    func sync(deadlines: [Deadline]) async {
        guard Self.isEnabled else { return }
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        await removeScheduled()

        var scheduled = 0
        let now = Date()
        for deadline in deadlines where deadline.dueDate > now {
            for offset in [24 * 3600.0, 1 * 3600.0] {
                let fireDate = deadline.dueDate.addingTimeInterval(-offset)
                guard fireDate > now.addingTimeInterval(30) else { continue }
                let request = UNNotificationRequest(
                    identifier: "\(Self.identifierPrefix)\(deadline.id).\(Int(offset))",
                    content: content(for: deadline, offset: offset),
                    trigger: trigger(for: fireDate)
                )
                try? await center.add(request)
                scheduled += 1
            }
        }
        #if DEBUG
        print("[notifications] scheduled \(scheduled) reminders")
        #endif
    }

    func sendTestNotification() async {
        await refreshAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "作业截止提醒"
        content.body = "这是一条测试通知。真正截止前 24 小时和 1 小时会再提醒你。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)test",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
        #if DEBUG
        print("[notifications] test notification scheduled")
        #endif
    }

    func clear() async {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Self.cachedAuthorization = authorizationStatus
        await removeScheduled()
    }

    private func removeScheduled() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func content(for deadline: Deadline, offset: TimeInterval) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let hours = Int(offset / 3600)
        content.title = hours == 24 ? "作业明天截止" : "作业即将截止"
        content.body = "\(deadline.courseName) · \(deadline.title)\n截止 \(SBDate.monthDay(deadline.dueDate)) \(SBDate.time(deadline.dueDate))"
        content.sound = .default
        content.threadIdentifier = deadline.courseID
        content.userInfo = [
            "deadlineID": deadline.id,
            "courseID": deadline.courseID
        ]
        return content
    }

    private func trigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.timeZone = TimeZone.current
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static var cachedAuthorization: UNAuthorizationStatus {
        get {
            UNAuthorizationStatus(rawValue: UserDefaults.standard.integer(forKey: authorizationKey)) ?? .notDetermined
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: authorizationKey)
        }
    }
}
