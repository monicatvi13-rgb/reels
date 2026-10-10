import Foundation

/// «Живой голос»: нейросетевая озвучка Яндекс SpeechKit.
/// Звучит как человек. Платно (оплата российской картой), ключ у каждого свой.
enum YandexSpeech {
    /// Голоса, которые подходят для разговора. У некоторых есть «доброжелательная» интонация.
    enum Voice: String, CaseIterable, Identifiable {
        case alena, jane, omazh, filipp, ermil, zahar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .alena: "Алёна · женский, тёплый"
            case .jane: "Джейн · женский, яркий"
            case .omazh: "Омаж · женский, спокойный"
            case .filipp: "Филипп · мужской, мягкий"
            case .ermil: "Ермил · мужской, бодрый"
            case .zahar: "Захар · мужской, деловой"
            }
        }

        /// Доброжелательная интонация — у тех голосов, которые её поддерживают.
        var emotion: String? {
            switch self {
            case .alena, .jane, .ermil: "good"
            default: nil
            }
        }
    }

    private static let keychainAccount = "yandex-speechkit-key"
    private static let endpoint = URL(string: "https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize")!

    static var savedKey: String? { KeychainStore.read(account: keychainAccount) }

    /// Ключ из Keychain, а если его нет — из переменной окружения (удобно при запуске из Xcode).
    static var apiKey: String? {
        if let key = savedKey { return key }
        if let key = ProcessInfo.processInfo.environment["YANDEX_SPEECHKIT_KEY"], !key.isEmpty { return key }
        return nil
    }

    static func saveKey(_ key: String) {
        KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: keychainAccount)
    }

    static func deleteKey() {
        KeychainStore.delete(account: keychainAccount)
    }

    enum SpeechError: LocalizedError {
        case unauthorized
        case api(Int, String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Яндекс не узнал ключ. Проверь, что он скопирован целиком."
            case .api(let code, let message): "Яндекс ответил ошибкой \(code): \(message)"
            }
        }
    }

    /// Превращает текст в звук (MP3).
    static func synthesize(_ text: String, voice: Voice, apiKey: String) async throws -> Data {
        // Яндекс принимает до 5000 символов за раз — длинные ответы аккуратно обрезаем.
        let clipped = String(text.prefix(4900))

        var fields: [(String, String)] = [
            ("text", clipped),
            ("lang", "ru-RU"),
            ("voice", voice.rawValue),
            ("speed", "1.0"),
            ("format", "mp3")
        ]
        if let emotion = voice.emotion {
            fields.append(("emotion", emotion))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Api-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(fields).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechError.api(0, "нет ответа") }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw SpeechError.unauthorized
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error_message
                ?? String(decoding: data, as: UTF8.self)
            throw SpeechError.api(http.statusCode, message)
        }
    }

    private struct ErrorBody: Decodable {
        let error_message: String
    }

    /// Кодирует поля формы так, чтобы «&», «+» и «=» в тексте не ломали запрос.
    private static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
            }
            .joined(separator: "&")
    }
}
