import Foundation

/// Нейросеть, которая работает «мозгом» приложения.
/// Всё остальное (голос, списки, интерфейс) от выбора не зависит.
enum AIProvider: String, CaseIterable, Identifiable {
    case gigachat
    case claude

    var id: String { rawValue }

    static let storageKey = "aiProvider"

    /// Выбранная сейчас нейросеть. По умолчанию — GigaChat: бесплатно и работает в России.
    static var current: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .gigachat }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    var title: String {
        switch self {
        case .gigachat: "GigaChat"
        case .claude: "Claude"
        }
    }

    var tagline: String {
        switch self {
        case .gigachat: "Бесплатно · работает в России"
        case .claude: "Платно · нужна иностранная карта"
        }
    }

    var keyName: String {
        switch self {
        case .gigachat: "Ключ авторизации"
        case .claude: "API-ключ"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .gigachat: "Вставь ключ авторизации"
        case .claude: "sk-ant-…"
        }
    }

    private var keychainAccount: String {
        switch self {
        case .gigachat: "gigachat-auth-key"
        case .claude: "anthropic-api-key"
        }
    }

    /// Имя переменной окружения — удобно при запуске из Xcode.
    private var environmentVariable: String {
        switch self {
        case .gigachat: "GIGACHAT_AUTH_KEY"
        case .claude: "ANTHROPIC_API_KEY"
        }
    }

    var savedKey: String? { KeychainStore.read(account: keychainAccount) }

    /// Ключ из Keychain, а если его там нет — из переменной окружения.
    var apiKey: String? {
        if let key = savedKey { return key }
        if let key = ProcessInfo.processInfo.environment[environmentVariable], !key.isEmpty { return key }
        return nil
    }

    func saveKey(_ key: String) {
        KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: keychainAccount)
    }

    func deleteKey() {
        KeychainStore.delete(account: keychainAccount)
    }

    func makeClient() -> LLMClient {
        switch self {
        case .gigachat: GigaChatClient()
        case .claude: ClaudeClient()
        }
    }
}
