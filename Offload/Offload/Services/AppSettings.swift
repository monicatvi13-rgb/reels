import Foundation

/// Где приложение хранит настройки: голос, уведомления, календарь.
/// Ключи используются и в @AppStorage на экранах, и в сервисах.
enum AppSettings {
    enum Key {
        static let voiceEnabled = "voiceEnabled"
        static let voiceIdentifier = "voiceIdentifier"
        static let morningDigest = "morningDigest"
        static let digestTime = "digestTime"
        static let itemReminders = "itemReminders"
        static let calendarMode = "calendarMode"
        static let assistantName = "assistantName"
        static let assistantStyle = "assistantStyle"
        static let speechPace = "speechPace"
    }

    /// Темп речи помощника.
    static var speechPace: SpeechPace {
        SpeechPace(rawValue: defaults.string(forKey: Key.speechPace) ?? "") ?? .calm
    }

    static let defaultAssistantName = "Джарвис"

    /// Как зовут помощника.
    static var assistantName: String {
        let name = (defaults.string(forKey: Key.assistantName) ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultAssistantName : name
    }

    static var assistantStyle: AssistantStyle {
        AssistantStyle(rawValue: defaults.string(forKey: Key.assistantStyle) ?? "") ?? .caring
    }

    private static var defaults: UserDefaults { .standard }

    /// Отвечать ли голосом. По умолчанию — да.
    static var voiceEnabled: Bool { defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true }

    /// Выбранный голос; пустая строка — лучший доступный русский.
    static var voiceIdentifier: String { defaults.string(forKey: Key.voiceIdentifier) ?? "" }

    /// Утренняя сводка дел.
    static var morningDigest: Bool { defaults.bool(forKey: Key.morningDigest) }

    /// Время утренней сводки в секундах от полуночи. По умолчанию 9:00.
    static var digestTime: Double { defaults.object(forKey: Key.digestTime) as? Double ?? defaultDigestTime }
    static let defaultDigestTime: Double = 9 * 3600

    /// Напоминание за 15 минут до дел, у которых указано время.
    static var itemReminders: Bool { defaults.bool(forKey: Key.itemReminders) }

    static var calendarMode: CalendarMode {
        CalendarMode(rawValue: defaults.string(forKey: Key.calendarMode) ?? "") ?? .none
    }
}

/// Куда отправлять дела с датой.
enum CalendarMode: String, CaseIterable, Identifiable {
    case none
    case calendar
    case reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Никуда"
        case .calendar: "В Календарь"
        case .reminders: "В Напоминания"
        }
    }
}

/// Характер помощника.
enum AssistantStyle: String, CaseIterable, Identifiable {
    case caring
    case business
    case humor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caring: "Заботливый"
        case .business: "Деловой"
        case .humor: "С юмором"
        }
    }

    /// Как это объяснить нейросети.
    var instruction: String {
        switch self {
        case .caring:
            "Ты тёплый и заботливый: поддерживаешь, замечаешь усталость, мягко подбадриваешь."
        case .business:
            "Ты деловой и чёткий: отвечаешь по существу, без лишних слов, как опытный ассистент руководителя."
        case .humor:
            "Ты с лёгким юмором и иронией, как Джарвис из фильмов: остроумно, но по делу и никогда не обидно."
        }
    }
}

/// Темп речи: спокойный звучит живее всего.
enum SpeechPace: String, CaseIterable, Identifiable {
    case calm
    case normal
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Спокойный"
        case .normal: "Обычный"
        case .fast: "Быстрый"
        }
    }

    /// Скорость для голоса Apple (обычная — 0,5).
    var rate: Float {
        switch self {
        case .calm: 0.46
        case .normal: 0.5
        case .fast: 0.55
        }
    }
}
