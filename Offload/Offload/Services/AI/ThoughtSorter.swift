import Foundation

/// Результат разбора: мысли, разложенные по полочкам.
struct SortedThoughts: Decodable {
    struct Entry: Decodable {
        let title: String
        /// Дата в формате ГГГГ-ММ-ДД или пустая строка, если даты нет.
        let date: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            date = (try? container.decodeIfPresent(String.self, forKey: .date)) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case title, date }
    }

    let comment: String
    let urgent: [Entry]
    let dated: [Entry]
    let ideas: [Entry]
    let home: [Entry]

    var count: Int { urgent.count + dated.count + ideas.count + home.count }

    // Разбор «с запасом»: если какой-то полочки нет в ответе, считаем её пустой.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comment = (try? container.decodeIfPresent(String.self, forKey: .comment)) ?? ""
        urgent = (try? container.decodeIfPresent([Entry].self, forKey: .urgent)) ?? []
        dated = (try? container.decodeIfPresent([Entry].self, forKey: .dated)) ?? []
        ideas = (try? container.decodeIfPresent([Entry].self, forKey: .ideas)) ?? []
        home = (try? container.decodeIfPresent([Entry].self, forKey: .home)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case comment, urgent, dated, ideas, home }
}

/// Раскладывает хаотичный текст по полочкам с помощью выбранной нейросети.
struct ThoughtSorter {
    var provider: AIProvider = .current

    func sort(_ text: String, today: Date = .now) async throws -> SortedThoughts {
        let reply = try await provider.makeClient().complete(
            system: Self.systemPrompt,
            messages: [LLMMessage(role: .user, text: "Сегодня \(Self.describe(today)).\n\nВот что у меня в голове:\n\(text)")],
            jsonSchema: Self.schema
        )
        guard let json = Self.extractJSON(from: reply),
              let sorted = try? JSONDecoder().decode(SortedThoughts.self, from: json)
        else { throw AIError.badResponse }
        return sorted
    }

    // MARK: - Инструкция для нейросети

    static let systemPrompt = """
    Ты — бережный помощник, который разгружает голову. Пользователь наговорил всё, \
    что у него в голове, хаотично и без структуры. Разложи это по четырём категориям:

    - urgent — срочное и то, что нужно сделать сегодня;
    - dated — дела и события, привязанные к конкретному дню или сроку (кроме сегодняшнего);
    - ideas — идеи, планы, мысли «на подумать»;
    - home — покупки и бытовые дела без конкретной даты.

    Правила:
    - Каждый пункт — короткая понятная формулировка на русском. Если это действие, \
      начинай с глагола («Купить молоко», «Позвонить маме»).
    - Разбивай перечисления на отдельные пункты: «купить хлеб и яйца» — это два пункта.
    - Ничего не выдумывай и не добавляй от себя. Если мысль не про дело, но важна, \
      положи её в ideas.
    - Поле date: дата в формате ГГГГ-ММ-ДД, если день назван прямо или относительно \
      («завтра», «в пятницу», «15 числа») — вычисли её от сегодняшней даты. \
      Если даты нет — пустая строка.
    - Поле comment: одна тёплая короткая фраза поддержки на русском (до 15 слов), \
      обращайся на «ты», без пафоса и без эмодзи.
    - Если категория пустая — верни пустой массив.

    Ответь ТОЛЬКО JSON-объектом, без пояснений и без markdown, строго такого вида:
    {"comment": "…", "urgent": [{"title": "…", "date": ""}], "dated": [{"title": "…", "date": "2026-10-03"}], "ideas": [], "home": []}
    """

    /// JSON-схема ответа. Claude соблюдает её гарантированно, GigaChat — по инструкции выше.
    static var schema: [String: Any] {
        let entry: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "date": ["type": "string"]
            ],
            "required": ["title", "date"],
            "additionalProperties": false
        ]
        let list: [String: Any] = ["type": "array", "items": entry]
        return [
            "type": "object",
            "properties": [
                "comment": ["type": "string"],
                "urgent": list,
                "dated": list,
                "ideas": list,
                "home": list
            ],
            "required": ["comment", "urgent", "dated", "ideas", "home"],
            "additionalProperties": false
        ]
    }

    // MARK: - Помощники

    /// Достаёт JSON из ответа, даже если нейросеть обернула его в ```json … ``` или добавила слова.
    static func extractJSON(from reply: String) -> Data? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(reply[start...end]).data(using: .utf8)
    }

    static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd, EEEE"
        return formatter.string(from: date)
    }

    static func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
