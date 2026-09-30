import Foundation

/// Одно сообщение в разговоре с нейросетью.
struct LLMMessage {
    enum Role: String {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

/// Общий «разъём» для любой нейросети: отправили инструкцию и сообщения — получили текст.
/// Благодаря ему приложение одинаково работает и с GigaChat, и с Claude.
protocol LLMClient {
    /// - Parameter jsonSchema: если нейросеть умеет строго соблюдать формат ответа, она его соблюдёт.
    ///   Остальные получают формат через инструкцию, а код подстраховывает разбор.
    func complete(system: String, messages: [LLMMessage], jsonSchema: [String: Any]?) async throws -> String
}

/// Понятные ошибки для любой нейросети.
enum AIError: LocalizedError {
    case noKey(AIProvider)
    case network(String)
    case unauthorized(AIProvider)
    case rateLimited
    case api(Int, String)
    case certificate
    case refusal
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey(let provider):
            "Нужен ключ \(provider.title). Нажми на значок вопроса — там пошаговая инструкция, это займёт пару минут."
        case .network(let message):
            "Не получилось достучаться до нейросети. Проверь интернет и попробуй ещё раз.\n\n\(message)"
        case .unauthorized(let provider):
            "\(provider.title) не узнал ключ. Проверь, что он скопирован целиком, без пробелов."
        case .rateLimited:
            "Слишком много запросов подряд. Подожди минутку и попробуй снова."
        case .api(let code, let message):
            "Нейросеть ответила ошибкой \(code): \(message)"
        case .certificate:
            "Не удалось установить защищённое соединение с GigaChat. В приложение не добавлен сертификат Минцифры — см. инструкцию в README."
        case .refusal:
            "Нейросеть не смогла обработать этот текст. Попробуй переформулировать."
        case .badResponse:
            "Ответ пришёл в непонятном виде. Попробуй ещё раз."
        }
    }
}
