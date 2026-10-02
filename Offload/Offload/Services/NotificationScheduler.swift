import Foundation
import UserNotifications

/// Уведомления: утренняя сводка и напоминания перед делами со временем.
/// Это локальные уведомления — они приходят на заблокированный экран
/// даже без интернета и без открытого приложения.
enum NotificationScheduler {
    private static let prefix = "offload."
    private static let reminderLead: TimeInterval = 15 * 60
    /// iOS хранит не больше 64 запланированных уведомлений на приложение.
    private static let maxItemReminders = 50

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    /// Пересобирает все уведомления по текущим спискам.
    static func reschedule(_ items: [ItemSnapshot], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard await isAuthorized() else { return }

        if AppSettings.morningDigest {
            scheduleMorningDigests(items, now: now, center: center)
        }
        if AppSettings.itemReminders {
            scheduleItemReminders(items, now: now, center: center)
        }
    }

    // MARK: - Утренняя сводка на неделю вперёд

    private static func scheduleMorningDigests(_ items: [ItemSnapshot], now: Date, center: UNUserNotificationCenter) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let fireDate = day.addingTimeInterval(AppSettings.digestTime)
            guard fireDate > now, let body = Briefing.morningText(for: day, items: items) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Доброе утро ☀️"
            content.body = body
            content.sound = .default

            add(id: "digest.\(offset)", content: content, at: fireDate, center: center)
        }
    }

    // MARK: - Напоминания перед делами со временем

    private static func scheduleItemReminders(_ items: [ItemSnapshot], now: Date, center: UNUserNotificationCenter) {
        let upcoming = items
            .filter { !$0.isDone && $0.hasTime }
            .compactMap { item -> (ItemSnapshot, Date)? in
                guard let due = item.dueDate, due > now else { return nil }
                let early = due.addingTimeInterval(-reminderLead)
                return (item, early > now ? early : due)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxItemReminders)

        for (index, entry) in upcoming.enumerated() {
            let (item, fireDate) = entry
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = "В \(Briefing.timeString(item.dueDate ?? fireDate)). Напоминаю заранее — у тебя есть 15 минут."
            content.sound = .default

            add(id: "item.\(index)", content: content, at: fireDate, center: center)
        }
    }

    private static func add(id: String, content: UNMutableNotificationContent, at date: Date, center: UNUserNotificationCenter) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
    }
}

/// Показывает уведомления, даже когда приложение открыто.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
