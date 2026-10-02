import Foundation

/// Действие, которое собеседник просит выполнить со списками.
struct AssistantAction: Decodable {
    enum Kind: String {
        case add, complete, uncomplete, reschedule, delete
    }

    let kind: Kind?
    /// Номер пункта из списка (для complete / uncomplete / reschedule / delete).
    let id: Int
    let title: String
    let category: String
    let date: String
    let time: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .type)) ?? "")
        id = (try? c.decode(Int.self, forKey: .id)) ?? -1
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        time = (try? c.decode(String.self, forKey: .time)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case type, id, title, category, date, time }
}

/// Ответ собеседника: что сказать и что сделать.
struct AssistantReply {
    let text: String
    var actions: [AssistantAction] = []
}

/// Собеседник: отвечает на вопросы о делах и выполняет команды.
/// С нейросетью — понимает любые вопросы и команды. Без неё — простые вопросы по спискам.
struct Assistant {
    struct Turn {
        let question: String
        let answer: String
    }

    var provider: AIProvider = .current

    /// - Parameter items: снимок списков; номер пункта в этом массиве — его id для нейросети.
    func respond(to question: String, items: [ItemSnapshot], history: [Turn], now: Date = .now) async -> AssistantReply {
        guard provider.apiKey != nil else {
            let text = LocalAnswerer.answer(question, items: items, now: now) ?? LocalAnswerer.fallback
            return AssistantReply(text: text)
        }

        var messages: [LLMMessage] = []
        for turn in history.suffix(6) {
            messages.append(LLMMessage(role: .user, text: turn.question))
            messages.append(LLMMessage(role: .assistant, text: turn.answer))
        }
        messages.append(LLMMessage(role: .user, text: question))

        do {
            let raw = try await provider.makeClient().complete(
                system: Self.systemPrompt(items: items, now: now),
                messages: messages,
                jsonSchema: Self.schema
            )
            return Self.parse(raw)
        } catch {
            // Нет связи с нейросетью — отвечаем сами, если вопрос простой.
            if let local = LocalAnswerer.answer(question, items: items, now: now) {
                return AssistantReply(text: local)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? "Не получилось ответить. Попробуй ещё раз."
            return AssistantReply(text: message)
        }
    }

    // MARK: - Разбор ответа

    private struct Payload: Decodable {
        let reply: String
        let actions: [AssistantAction]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reply = (try? c.decode(String.self, forKey: .reply)) ?? ""
            actions = (try? c.decode([AssistantAction].self, forKey: .actions)) ?? []
        }

        private enum CodingKeys: String, CodingKey { case reply, actions }
    }

    static func parse(_ raw: String) -> AssistantReply {
        if let json = ThoughtSorter.extractJSON(from: raw),
           let payload = try? JSONDecoder().decode(Payload.self, from: json),
           !payload.reply.isEmpty || !payload.actions.isEmpty {
            let text = payload.reply.isEmpty ? "Готово." : payload.reply
            return AssistantReply(text: cleanForSpeech(text), actions: payload.actions.filter { $0.kind != nil })
        }
        // Нейросеть ответила обычным текстом — просто говорим его.
        return AssistantReply(text: cleanForSpeech(raw))
    }

    // MARK: - Инструкция для нейросети

    static func systemPrompt(items: [ItemSnapshot], now: Date) -> String {
        """
        Ты — Offload, личный голосовой помощник в телефоне. Ты как Джарвис: \
        спокойный, тёплый, немного остроумный, всегда на стороне пользователя. \
        Помогаешь не держать всё в голове: отвечаешь на вопросы и ведёшь списки дел.

        Как отвечать (поле reply):
        - По-русски, на «ты», коротко: обычно 1–2 предложения. Твой ответ прочитают вслух.
        - Без списков с маркерами, без markdown, без эмодзи — только живая речь.
        - О делах говори только то, что есть в списках ниже. Ничего не выдумывай.
        - Время называй по-человечески: «в десять утра», «завтра», «в пятницу».
        - Если выполнил действие — коротко подтверди, что сделано.

        Действия (поле actions) — только если пользователь явно просит что-то \
        добавить, напомнить, отметить, перенести или удалить. На обычные вопросы — пустой массив.
        - add — новый пункт: title (коротко, с глагола: «Позвонить маме»), category, date, time.
          Если сказано «напомни» — обязательно поставь дату (и время, если названо).
          Несколько вещей сразу («молоко и хлеб») — отдельное действие на каждую.
        - complete — пользователь сделал дело («я позвонила маме»): id пункта.
        - uncomplete — вернуть в работу: id пункта.
        - reschedule — перенести: id пункта, новые date и/или time.
        - delete — удалить: id пункта. Только если об этом прямо попросили.
        Категории: urgent — срочное и сегодня; dated — с конкретной датой; \
        ideas — идеи и мысли; home — покупки и быт.
        date — ГГГГ-ММ-ДД, вычисляй от текущей даты; time — ЧЧ:ММ. Если чего-то нет — пустая строка, \
        у ненужного id ставь -1. Если не уверен, о каком пункте речь, — ничего не делай и переспроси.

        Ответь ТОЛЬКО JSON-объектом, без пояснений и markdown:
        {"reply": "…", "actions": [{"type": "add", "id": -1, "title": "…", "category": "dated", "date": "2026-10-03", "time": "10:00"}]}

        Сейчас: \(describe(now)).

        Списки пользователя (в квадратных скобках — id пункта):
        \(context(items: items))
        """
    }

    static var schema: [String: Any] {
        let action: [String: Any] = [
            "type": "object",
            "properties": [
                "type": ["type": "string", "enum": ["add", "complete", "uncomplete", "reschedule", "delete"]],
                "id": ["type": "integer"],
                "title": ["type": "string"],
                "category": ["type": "string", "enum": ["urgent", "dated", "ideas", "home", ""]],
                "date": ["type": "string"],
                "time": ["type": "string"]
            ],
            "required": ["type", "id", "title", "category", "date", "time"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": [
                "reply": ["type": "string"],
                "actions": ["type": "array", "items": action]
            ],
            "required": ["reply", "actions"],
            "additionalProperties": false
        ]
    }

    private static func context(items: [ItemSnapshot]) -> String {
        guard !items.isEmpty else { return "(списки пока пустые)" }
        let indexed = Array(items.enumerated())

        var lines: [String] = []
        for category in ItemCategory.allCases {
            let group = indexed.filter { !$0.element.isDone && $0.element.category == category }
            guard !group.isEmpty else { continue }
            lines.append("\(category.title):")
            lines += group.prefix(60).map { "- [\($0.offset)] \(line(for: $0.element))" }
        }
        let done = indexed.filter { $0.element.isDone }.prefix(15)
        if !done.isEmpty {
            lines.append("Уже сделано:")
            lines += done.map { "- [\($0.offset)] \($0.element.title)" }
        }
        return lines.joined(separator: "\n")
    }

    private static func line(for item: ItemSnapshot) -> String {
        guard let date = item.dueDate else { return item.title }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = item.hasTime ? "yyyy-MM-dd (d MMMM, EEEE), HH:mm" : "yyyy-MM-dd (d MMMM, EEEE)"
        return "\(item.title) — \(formatter.string(from: date))"
    }

    private static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd (d MMMM, EEEE), HH:mm"
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
