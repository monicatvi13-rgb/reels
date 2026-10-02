import Foundation

/// Простая копия пункта списка — её удобно передавать в уведомления и в нейросеть.
struct ItemSnapshot {
    let title: String
    let category: ItemCategory
    let dueDate: Date?
    let hasTime: Bool
    let isDone: Bool

    init(_ item: OffloadItem) {
        title = item.title
        category = item.category
        dueDate = item.dueDate
        hasTime = item.hasTime
        isDone = item.isDone
    }
}

/// Собирает живые фразы о делах: для утренней сводки и для ответов голосом.
/// Работает без нейросети — только по спискам.
enum Briefing {
    private static var calendar: Calendar { .current }

    // MARK: - Подборки

    static func items(on day: Date, from items: [ItemSnapshot]) -> [ItemSnapshot] {
        items
            .filter { !$0.isDone }
            .filter { item in
                guard let date = item.dueDate else { return false }
                return calendar.isDate(date, inSameDayAs: day)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    static func urgent(from items: [ItemSnapshot]) -> [ItemSnapshot] {
        items.filter { !$0.isDone && $0.category == .urgent && $0.dueDate == nil }
    }

    /// Всё на сегодня: дела с сегодняшней датой и срочное без даты.
    static func today(from items: [ItemSnapshot], now: Date = .now) -> [ItemSnapshot] {
        Self.items(on: now, from: items) + urgent(from: items)
    }

    // MARK: - Фразы

    /// «позвонить маме, стоматолог в 10:00 и купить торт»
    static func list(_ items: [ItemSnapshot], limit: Int = 6) -> String {
        let phrases = items.prefix(limit).map(phrase)
        var text: String
        switch phrases.count {
        case 0: return ""
        case 1: text = phrases[0]
        default: text = phrases.dropLast().joined(separator: ", ") + " и " + phrases.last!
        }
        if items.count > limit {
            text += " — и ещё \(items.count - limit)"
        }
        return text
    }

    static func phrase(_ item: ItemSnapshot) -> String {
        var text = item.title.lowercasedFirst
        if item.hasTime, let date = item.dueDate {
            text += " в \(timeString(date))"
        }
        return text
    }

    static func count(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod10 == 1 && mod100 != 11 { word = "дело" }
        else if (2...4).contains(mod10) && !(12...14).contains(mod100) { word = "дела" }
        else { word = "дел" }
        return "\(n) \(word)"
    }

    static func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    // MARK: - Утренняя сводка

    /// Текст уведомления на утро конкретного дня. nil — если сказать нечего.
    static func morningText(for day: Date, items: [ItemSnapshot]) -> String? {
        let dated = Self.items(on: day, from: items)
        let urgent = urgent(from: items)
        guard !dated.isEmpty || !urgent.isEmpty else { return nil }

        var parts: [String] = []
        if !dated.isEmpty {
            parts.append("Сегодня: \(list(dated, limit: 4)).")
        }
        if !urgent.isEmpty {
            parts.append(dated.isEmpty
                ? "Срочное: \(list(urgent, limit: 3))."
                : "И ещё срочное: \(list(urgent, limit: 2)).")
        }
        return parts.joined(separator: " ").capitalizedFirst
    }
}

// MARK: - Ответы без нейросети

/// Отвечает на простые вопросы по спискам, когда нейросеть не подключена.
enum LocalAnswerer {
    static func answer(_ question: String, items: [ItemSnapshot], now: Date = .now) -> String? {
        let q = question.lowercased()
        let calendar = Calendar.current

        if q.contains("послезавтра") {
            let day = calendar.date(byAdding: .day, value: 2, to: now)!
            return dayAnswer(Briefing.items(on: day, from: items), when: "Послезавтра")
        }
        if q.contains("завтра") {
            let day = calendar.date(byAdding: .day, value: 1, to: now)!
            return dayAnswer(Briefing.items(on: day, from: items), when: "Завтра")
        }
        if q.contains("сегодня") || q.contains("сейчас") {
            return dayAnswer(Briefing.today(from: items, now: now), when: "Сегодня")
        }
        if q.contains("недел") {
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            let week = items
                .filter { !$0.isDone }
                .filter { guard let d = $0.dueDate else { return false }; return d >= start && d < end }
                .sorted { $0.dueDate! < $1.dueDate! }
            guard !week.isEmpty else { return "На ближайшую неделю дел с датами нет. Свободная неделя!" }
            return "На неделе \(Briefing.count(week.count)): \(Briefing.list(week.map(withWeekday), limit: 6))."
        }
        if q.contains("куп") || q.contains("магазин") || q.contains("быт") || q.contains("дом") {
            return categoryAnswer(.home, items: items,
                                  intro: "Из покупок и бытовых дел",
                                  empty: "Список покупок пуст — можно не заходить в магазин.")
        }
        if q.contains("иде") || q.contains("подума") {
            return categoryAnswer(.ideas, items: items,
                                  intro: "Твои идеи",
                                  empty: "Идей пока не записано. Расскажи, что пришло в голову — я сохраню.")
        }
        if q.contains("срочн") || q.contains("горит") {
            let urgent = Briefing.urgent(from: items)
            return urgent.isEmpty
                ? "Ничего не горит. Можно выдохнуть."
                : "Срочное: \(Briefing.list(urgent))."
        }
        if q.contains("что у меня") || q.contains("какие дела") || q.contains("план") {
            return dayAnswer(Briefing.today(from: items, now: now), when: "Сегодня")
        }
        return nil
    }

    static let fallback = "Без нейросети я понимаю вопросы про сегодня, завтра, неделю, срочное, покупки и идеи. Подключи нейросеть — и я смогу ответить на что угодно."

    private static func dayAnswer(_ list: [ItemSnapshot], when: String) -> String {
        guard !list.isEmpty else { return "\(when) дел нет. Можно выдохнуть." }
        return "\(when) у тебя \(Briefing.count(list.count)): \(Briefing.list(list))."
    }

    private static func categoryAnswer(_ category: ItemCategory, items: [ItemSnapshot], intro: String, empty: String) -> String {
        let list = items.filter { !$0.isDone && $0.category == category }
        guard !list.isEmpty else { return empty }
        return "\(intro): \(Briefing.list(list))."
    }

    /// Добавляет день недели к пункту: «стоматолог (пятница)».
    private static func withWeekday(_ item: ItemSnapshot) -> ItemSnapshot {
        guard let date = item.dueDate else { return item }
        let weekday = date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "ru_RU")))
        return ItemSnapshot(title: "\(item.title) (\(weekday))", category: item.category,
                            dueDate: date, hasTime: item.hasTime, isDone: item.isDone)
    }
}

extension ItemSnapshot {
    init(title: String, category: ItemCategory, dueDate: Date?, hasTime: Bool, isDone: Bool) {
        self.title = title
        self.category = category
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.isDone = isDone
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
