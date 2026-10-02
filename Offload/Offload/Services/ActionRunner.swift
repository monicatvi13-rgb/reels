import Foundation
import SwiftData

/// Выполняет команды собеседника: добавить, отметить, перенести, удалить.
/// Календарь и уведомления подтянутся сами — их обновляет AppSync после любых изменений.
@MainActor
struct ActionRunner {
    let context: ModelContext

    /// - Parameter items: тот же снимок, что ушёл в нейросеть; id действия — номер пункта в нём.
    /// - Returns: короткие строки о сделанном — их видно под ответом.
    func run(_ actions: [AssistantAction], on items: [OffloadItem], now: Date = .now) -> [String] {
        var log: [String] = []
        var deleted = Set<Int>()

        for action in actions {
            guard let kind = action.kind else { continue }

            switch kind {
            case .add:
                let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let due = ThoughtSorter.parseDue(date: action.date, time: action.time, today: now)
                let category = ItemCategory(rawValue: action.category)
                    ?? (due.date != nil ? .dated : .urgent)
                let item = OffloadItem(title: title, category: category, dueDate: due.date, hasTime: due.hasTime)
                context.insert(item)
                log.append("＋ \(title)\(Self.when(item))")

            case .complete, .uncomplete:
                guard let item = item(at: action.id, in: items, deleted: deleted) else { continue }
                item.isDone = kind == .complete
                log.append(kind == .complete ? "✓ \(item.title)" : "↺ \(item.title) — снова в работе")

            case .reschedule:
                guard let item = item(at: action.id, in: items, deleted: deleted) else { continue }
                let newDay = ThoughtSorter.parseDate(action.date)
                let hasNewTime = !action.time.isEmpty
                // Назвали только время — оставляем прежний день (или сегодня).
                let day = newDay ?? item.dueDate ?? now
                let due = ThoughtSorter.parseDue(
                    date: Self.dayString(day),
                    time: hasNewTime ? action.time : (item.hasTime ? item.dueDate.map(Self.timeString) ?? "" : ""),
                    today: now
                )
                guard let date = due.date else { continue }
                item.dueDate = date
                item.hasTime = due.hasTime
                if item.category == .ideas || item.category == .home {
                    item.category = .dated
                }
                log.append("→ \(item.title)\(Self.when(item))")

            case .delete:
                guard let item = item(at: action.id, in: items, deleted: deleted) else { continue }
                deleted.insert(action.id)
                log.append("✕ \(item.title)")
                CalendarSync.shared.remove(item)
                context.delete(item)
            }
        }

        try? context.save()
        return log
    }

    private func item(at id: Int, in items: [OffloadItem], deleted: Set<Int>) -> OffloadItem? {
        guard items.indices.contains(id), !deleted.contains(id) else { return nil }
        return items[id]
    }

    /// « · завтра, 10:00»
    private static func when(_ item: OffloadItem) -> String {
        guard let date = item.dueDate else { return "" }
        return " · " + ItemRow.format(date, hasTime: item.hasTime).lowercased()
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
