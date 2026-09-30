import Foundation
import Security

/// Подключение к GigaChat API (Сбер).
///
/// Как это работает:
/// 1. По «ключу авторизации» пользователя получаем временный токен (живёт 30 минут).
/// 2. С этим токеном отправляем сообщения в чат.
/// Серверы GigaChat используют сертификат Минцифры, поэтому соединение
/// проверяется через файл сертификата, вложенный в приложение.
struct GigaChatClient: LLMClient {
    private let chatURL = URL(string: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions")!
    private let model = "GigaChat-2-Max"

    func complete(system: String, messages: [LLMMessage], jsonSchema: [String: Any]?) async throws -> String {
        guard let authKey = AIProvider.gigachat.apiKey else { throw AIError.noKey(.gigachat) }

        do {
            return try await send(system: system, messages: messages, authKey: authKey, forceNewToken: false)
        } catch AIError.unauthorized(.gigachat) {
            // Токен мог истечь раньше времени — берём новый и пробуем ещё раз.
            return try await send(system: system, messages: messages, authKey: authKey, forceNewToken: true)
        }
    }

    private func send(system: String, messages: [LLMMessage], authKey: String, forceNewToken: Bool) async throws -> String {
        let token = try await GigaChatTokenStore.shared.token(for: authKey, forceNew: forceNewToken)

        var chat: [[String: String]] = [["role": "system", "content": system]]
        chat += messages.map { ["role": $0.role.rawValue, "content": $0.text] }

        let body: [String: Any] = [
            "model": model,
            "messages": chat,
            "temperature": 0.2
        ]

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await GigaChatNetwork.perform(request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = response.choices.first?.message.content, !text.isEmpty else {
            throw AIError.badResponse
        }
        return text
    }
}

// MARK: - Токен доступа

/// Хранит временный токен и обновляет его, когда он вот-вот истечёт.
actor GigaChatTokenStore {
    static let shared = GigaChatTokenStore()

    private let oauthURL = URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!
    private var cached: (key: String, token: String, expiresAt: Date)?

    func token(for authKey: String, forceNew: Bool) async throws -> String {
        if !forceNew, let cached, cached.key == authKey, cached.expiresAt > .now.addingTimeInterval(60) {
            return cached.token
        }

        var request = URLRequest(url: oauthURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "RqUID")
        request.setValue("Basic \(authKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("scope=GIGACHAT_API_PERS".utf8)

        let data = try await GigaChatNetwork.perform(request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Date(timeIntervalSince1970: response.expires_at / 1000)
        cached = (authKey, response.access_token, expiresAt)
        return response.access_token
    }
}

// MARK: - Сеть с сертификатом Минцифры

enum GigaChatNetwork {
    private static let session = URLSession(
        configuration: .default,
        delegate: RussianTrustDelegate(),
        delegateQueue: nil
    )

    static func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.isCertificateError(error) {
            throw AIError.certificate
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw AIError.unauthorized(.gigachat)
        case 429: throw AIError.rateLimited
        default:
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.message
                ?? String(decoding: data, as: UTF8.self)
            throw AIError.api(http.statusCode, message)
        }
    }

    private static func isCertificateError(_ error: URLError) -> Bool {
        [.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
         .serverCertificateHasUnknownRoot, .secureConnectionFailed, .cancelled].contains(error.code)
    }
}

/// Доверяет серверам, подписанным сертификатами Минцифры, которые лежат в приложении:
/// russian_trusted_root_ca (корневой, обязателен) и russian_trusted_sub_ca (промежуточный, желательно).
/// Обычные сертификаты тоже продолжают работать.
final class RussianTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let certificates: [SecCertificate] = ["russian_trusted_root_ca", "russian_trusted_sub_ca"]
        .compactMap(RussianTrustDelegate.loadCertificate(named:))

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              !certificates.isEmpty else {
            return (.performDefaultHandling, nil)
        }

        SecTrustSetAnchorCertificates(trust, certificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)

        if SecTrustEvaluateWithError(trust, nil) {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    private static func loadCertificate(named name: String) -> SecCertificate? {
        for ext in ["cer", "crt", "pem", "der"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let raw = try? Data(contentsOf: url) else { continue }
            if let certificate = SecCertificateCreateWithData(nil, raw as CFData) {
                return certificate
            }
            // Файл в текстовом формате PEM — достаём из него двоичные данные.
            if let text = String(data: raw, encoding: .utf8) {
                let base64 = text
                    .components(separatedBy: .newlines)
                    .filter { !$0.hasPrefix("-----") }
                    .joined()
                if let der = Data(base64Encoded: base64),
                   let certificate = SecCertificateCreateWithData(nil, der as CFData) {
                    return certificate
                }
            }
        }
        return nil
    }
}

// MARK: - Формат ответов GigaChat

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_at: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct ErrorResponse: Decodable {
    let message: String
}
