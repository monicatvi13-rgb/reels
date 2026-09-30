import Foundation

/// Результат, который возвращает Claude: мысли, разложенные по полочкам.
struct SortedThoughts: Decodable {
    struct Entry: Decodable {
        let title: String
        /// Дата в формате ГГГГ-ММ-ДД или пустая строка, если даты нет.
        let date: String
    }

    let comment: String
    let urgent: [Entry]
    let dated: [Entry]
    let ideas: [Entry]
    let home: [Entry]

    var count: Int { urgent.count + dated.count + ideas.count + home.count }
}

/// Отправляет текст в Claude API и получает обратно структурированный JSON.
struct ClaudeService {
    enum ServiceError: LocalizedError {
        case noKey
        case network(String)
        case api(Int, String)
        case refusal
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noKey:
                "Нужен ключ Claude API. Добавь его в настройках — это займёт минуту."
            case .network(let message):
                "Не получилось достучаться до Claude. Проверь интернет и попробуй ещё раз.\n\n\(message)"
            case .api(401, _):
                "Claude не узнал ключ. Проверь, что он скопирован целиком."
            case .api(429, _):
                "Слишком много запросов подряд. Подожди минутку и попробуй снова."
            case .api(let code, let message):
                "Claude ответил ошибкой \(code): \(message)"
            case .refusal:
                "Claude не смог обработать этот текст. Попробуй переформулировать."
            case .badResponse:
                "Ответ пришёл в непонятном виде. Попробуй ещё раз."
            }
        }
    }

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-5-5"

    private let systemPrompt = """
    Ты — бережный помощник, который разгружает голову. Пользовательница наговорила \
    всё, что у неё в голове, хаотично и без структуры. Разложи это по четырём категориям:

    - urgent — срочное и то, что нужно сделать сегодня;
    - dated — дела и события, привязанные к конкретному дню или сроку (кроме сегодняшнего);
    - ideas — идеи, планы, мысли «на подумать»;
    - home — покупки и бытовые дела без конкретной даты.

    Правила:
    - Каждый пункт — короткая понятная формулировка на русском, начинай с глагола, \
      если это действие («Купить молоко», «Позвонить маме»).
    - Разбивай перечисления на отдельные пункты: «купить хлеб и яйца» — это два пункта.
    - Ничего не выдумывай и не добавляй от себя. Если мысль не про дело, но важна, \
      положи её в ideas.
    - Поле date: дата в формате ГГГГ-ММ-ДД, если день назван прямо или относительно \
      («завтра», «в пятницу», «15 числа») — вычисли её от сегодняшней даты. \
      Если даты нет — пустая строка.
    - Поле comment: одна тёплая короткая фраза поддержки на русском (до 15 слов), \
      обращайся на «ты», без пафоса и без эмодзи.
    - Если категория пустая — верни пустой массив.
    """

    /// JSON-схема ответа. Structured outputs гарантируют, что Claude вернёт именно её.
    private var schema: [String: Any] {
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

    func sort(_ text: String, today: Date = .now) async throws -> SortedThoughts {
        guard let apiKey = KeychainStore.apiKey else { throw ServiceError.noKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Сегодня \(Self.todayDescription(today)).\n\nВот что у меня в голове:\n\(text)"]
            ],
            // effort "low" — быстрый ответ: задача несложная, а ждать на телефоне не хочется.
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema]
            ],
            // Если Claude откажется отвечать, сервер сам попробует запасную модель.
            "fallbacks": "default"
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error.message
                ?? String(decoding: data, as: UTF8.self)
            throw ServiceError.api(http.statusCode, message)
        }

        let message = try JSONDecoder().decode(APIMessage.self, from: data)
        if message.stop_reason == "refusal" { throw ServiceError.refusal }

        // В ответе могут быть служебные блоки размышлений — берём только текст.
        guard let json = message.content.first(where: { $0.type == "text" })?.text,
              let jsonData = json.data(using: .utf8),
              let sorted = try? JSONDecoder().decode(SortedThoughts.self, from: jsonData)
        else { throw ServiceError.badResponse }

        return sorted
    }

    private static func todayDescription(_ date: Date) -> String {
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

// MARK: - Формат ответа API

private struct APIMessage: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
    let stop_reason: String?
}

private struct APIErrorBody: Decodable {
    struct Inner: Decodable { let message: String }
    let error: Inner
}
