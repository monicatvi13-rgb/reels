import Foundation

/// Одна точка, которая после любых изменений в списках
/// обновляет уведомления и Календарь.
@MainActor
enum AppSync {
    static func refresh(_ items: [OffloadItem]) async {
        CalendarSync.shared.syncAll(items)
        await NotificationScheduler.reschedule(items.map { ItemSnapshot($0) })
    }

    /// «Отпечаток» списков: если он поменялся — пора синхронизировать.
    static func signature(of items: [OffloadItem]) -> String {
        items.map {
            "\($0.title)|\($0.categoryRaw)|\($0.dueDate?.timeIntervalSince1970 ?? 0)|\($0.hasTime)|\($0.isDone)"
        }
        .joined(separator: "\n")
    }
}
