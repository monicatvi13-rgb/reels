import Foundation

/// Собеседник: отвечает на вопросы о твоих делах.
/// С нейросетью — на любые вопросы. Без неё — на простые, по спискам.
struct Assistant {
    struct Turn {
        let question: String
        let answer: String
    }

    var provider: AIProvider = .current

    func answer(_ question: String, items: [ItemSnapshot], history: [Turn], now: Date = .now) async -> String {
        guard provider.apiKey != nil else {
            return LocalAnswerer.answer(question, items: items, now: now) ?? LocalAnswerer.fallback
        }

        var messages: [LLMMessage] = []
        for turn in history.suffix(6) {
            messages.append(LLMMessage(role: .user, text: turn.question))
            messages.append(LLMMessage(role: .assistant, text: turn.answer))
        }
        messages.append(LLMMessage(role: .user, text: question))

        do {
            let reply = try await provider.makeClient().complete(
                system: Self.systemPrompt(items: items, now: now),
                messages: messages,
                jsonSchema: nil
            )
            return Self.cleanForSpeech(reply)
        } catch {
            // Нет связи с нейросетью — отвечаем сами, если вопрос простой.
            if let local = LocalAnswerer.answer(question, items: items, now: now) {
                return local
            }
            return (error as? LocalizedError)?.errorDescription ?? "Не получилось ответить. Попробуй ещё раз."
        }
    }

    // MARK: - Инструкция для нейросети

    static func systemPrompt(items: [ItemSnapshot], now: Date) -> String {
        """
        Ты — Offload, личный голосовой помощник в телефоне. Ты как Джарвис: \
        спокойный, тёплый, немного остроумный, всегда на стороне пользователя. \
        Помогаешь не держать всё в голове.

        Как отвечать:
        - По-русски, на «ты», коротко: обычно 1–3 предложения. Твой ответ прочитают вслух.
        - Без списков с маркерами, без markdown, без эмодзи — только живая речь.
        - О делах говори только то, что есть в списках ниже. Ничего не выдумывай. \
          Если в списках этого нет — честно скажи.
        - Время называй по-человечески: «в десять утра», «завтра», «в пятницу».
        - На общие вопросы (совет, идея, поддержка) отвечай по существу, \
          но так же коротко и по-дружески.

        Сейчас: \(describe(now)).

        Списки пользователя:
        \(context(items: items, now: now))
        """
    }

    private static func context(items: [ItemSnapshot], now: Date) -> String {
        let active = items.filter { !$0.isDone }
        let done = items.filter(\.isDone).prefix(10)
        guard !items.isEmpty else { return "(списки пока пустые)" }

        var lines: [String] = []
        for category in ItemCategory.allCases {
            let group = active.filter { $0.category == category }
            guard !group.isEmpty else { continue }
            lines.append("\(category.title):")
            lines += group.prefix(40).map { "- \(line(for: $0))" }
        }
        if !done.isEmpty {
            lines.append("Уже сделано:")
            lines += done.map { "- \($0.title)" }
        }
        return lines.joined(separator: "\n")
    }

    private static func line(for item: ItemSnapshot) -> String {
        guard let date = item.dueDate else { return item.title }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = item.hasTime ? "d MMMM, EEEE, HH:mm" : "d MMMM, EEEE"
        return "\(item.title) — \(formatter.string(from: date))"
    }

    private static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, EEEE, HH:mm"
        return formatter.string(from: date)
    }

    /// Убирает разметку, которую голос прочитал бы вслух («звёздочка», «решётка»).
    static func cleanForSpeech(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
