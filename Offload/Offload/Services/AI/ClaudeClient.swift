import Foundation

/// Подключение к Claude API (Anthropic).
struct ClaudeClient: LLMClient {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-5-5"

    func complete(system: String, messages: [LLMMessage], jsonSchema: [String: Any]?) async throws -> String {
        guard let apiKey = AIProvider.claude.apiKey else { throw AIError.noKey(.claude) }

        // effort "low" — быстрый ответ: задачи простые, а ждать на телефоне не хочется.
        var outputConfig: [String: Any] = ["effort": "low"]
        if let jsonSchema {
            // Structured outputs: Claude гарантированно вернёт JSON нужной формы.
            outputConfig["format"] = ["type": "json_schema", "schema": jsonSchema]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            "output_config": outputConfig,
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
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw AIError.unauthorized(.claude)
        case 429: throw AIError.rateLimited
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                ?? String(decoding: data, as: UTF8.self)
            throw AIError.api(http.statusCode, message)
        }

        let message = try JSONDecoder().decode(MessageBody.self, from: data)
        if message.stop_reason == "refusal" { throw AIError.refusal }

        // В ответе могут быть служебные блоки размышлений — берём только текст.
        let text = message.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard !text.isEmpty else { throw AIError.badResponse }
        return text
    }
}

private struct MessageBody: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
    let stop_reason: String?
}

private struct ErrorBody: Decodable {
    struct Inner: Decodable { let message: String }
    let error: Inner
}
