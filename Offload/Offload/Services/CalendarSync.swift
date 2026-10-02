import Foundation
import EventKit

/// Отправляет дела с датой в системный Календарь или в «Напоминания».
/// Если пункт поменяли в Offload — событие обновится. Если событие удалили
/// в Календаре вручную — Offload не будет создавать его заново.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()

    private init() {}

    // MARK: - Доступ

    static func hasAccess(for mode: CalendarMode) -> Bool {
        switch mode {
        case .none: true
        case .calendar: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .reminders: EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        }
    }

    func requestAccess(for mode: CalendarMode) async -> Bool {
        do {
            switch mode {
            case .none: return true
            case .calendar: return try await store.requestFullAccessToEvents()
            case .reminders: return try await store.requestFullAccessToReminders()
            }
        } catch {
            return false
        }
    }

    // MARK: - Синхронизация

    func syncAll(_ items: [OffloadItem]) {
        let mode = AppSettings.calendarMode
        guard mode != .none, Self.hasAccess(for: mode) else { return }
        store.refreshSourcesIfNecessary()
        for item in items {
            switch mode {
            case .none: break
            case .calendar: syncEvent(item)
            case .reminders: syncReminder(item)
            }
        }
    }

    /// Убирает связанные событие и напоминание — вызывается перед удалением пункта.
    func remove(_ item: OffloadItem) {
        if let id = item.calendarEventID,
           Self.hasAccess(for: .calendar),
           let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
        if let id = item.reminderID,
           Self.hasAccess(for: .reminders),
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
        item.calendarEventID = nil
        item.reminderID = nil
    }

    // MARK: - Календарь

    private func syncEvent(_ item: OffloadItem) {
        let existing = item.calendarEventID.flatMap { store.event(withIdentifier: $0) }

        guard let date = item.dueDate else {
            // Дату убрали — убираем и событие.
            if let existing { try? store.remove(existing, span: .thisEvent, commit: true) }
            item.calendarEventID = nil
            return
        }
        // Событие удалили в Календаре вручную — уважаем это решение.
        if item.calendarEventID != nil && existing == nil { return }
        // Новые события создаём только для невыполненных дел.
        if existing == nil && item.isDone { return }

        let event = existing ?? EKEvent(eventStore: store)
        if existing == nil {
            guard let calendar = store.defaultCalendarForNewEvents else { return }
            event.calendar = calendar
            event.notes = "Добавлено из Offload"
        }

        if event.title != item.title { event.title = item.title }

        let calendar = Calendar.current
        if item.hasTime {
            let end = date.addingTimeInterval(3600)
            if event.isAllDay { event.isAllDay = false }
            if event.startDate != date { event.startDate = date }
            if event.endDate != end { event.endDate = end }
        } else {
            let start = calendar.startOfDay(for: date)
            if !event.isAllDay { event.isAllDay = true }
            if event.startDate != start { event.startDate = start }
            if event.endDate != start { event.endDate = start }
        }

        guard existing == nil || event.hasChanges else { return }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            item.calendarEventID = event.eventIdentifier
        } catch {
            // Не получилось — попробуем при следующей синхронизации.
        }
    }

    // MARK: - Напоминания

    private static func sameMoment(_ lhs: DateComponents?, _ rhs: DateComponents) -> Bool {
        guard let lhs else { return false }
        return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
            && lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }

    private func syncReminder(_ item: OffloadItem) {
        let existing = item.reminderID.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }

        guard let date = item.dueDate else {
            if let existing { try? store.remove(existing, commit: true) }
            item.reminderID = nil
            return
        }
        if item.reminderID != nil && existing == nil { return }
        if existing == nil && item.isDone { return }

        let reminder = existing ?? EKReminder(eventStore: store)
        if existing == nil {
            guard let list = store.defaultCalendarForNewReminders() else { return }
            reminder.calendar = list
            reminder.notes = "Добавлено из Offload"
        }

        if reminder.title != item.title { reminder.title = item.title }
        if reminder.isCompleted != item.isDone { reminder.isCompleted = item.isDone }

        let units: Set<Calendar.Component> = item.hasTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        let components = Calendar.current.dateComponents(units, from: date)
        if !Self.sameMoment(reminder.dueDateComponents, components) {
            reminder.dueDateComponents = components
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            if item.hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        guard existing == nil || reminder.hasChanges else { return }
        do {
            try store.save(reminder, commit: true)
            item.reminderID = reminder.calendarItemIdentifier
        } catch {
            // Не получилось — попробуем при следующей синхронизации.
        }
    }
}
