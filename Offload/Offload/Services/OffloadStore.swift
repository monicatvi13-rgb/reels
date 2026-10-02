import Foundation
import SwiftData

/// Общее хранилище данных: им пользуются и экраны приложения, и Siri.
@MainActor
enum OffloadStore {
    static let container: ModelContainer = {
        let schema = Schema([BrainDump.self, OffloadItem.self, ChatEntry.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            // Если хранилище не открылось — работаем во временном, чтобы приложение не падало.
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()
}

/// Память разговора: сохраняет реплики и отдаёт последние для контекста.
@MainActor
enum ChatMemory {
    /// Сколько реплик храним — старые удаляются.
    static let limit = 200

    static func all(in context: ModelContext) -> [ChatEntry] {
        let descriptor = FetchDescriptor<ChatEntry>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func turns(from entries: [ChatEntry]) -> [Assistant.Turn] {
        var result: [Assistant.Turn] = []
        var pendingQuestion: String?
        for entry in entries {
            if entry.isUser {
                pendingQuestion = entry.text
            } else if let question = pendingQuestion {
                result.append(Assistant.Turn(question: question, answer: entry.text))
                pendingQuestion = nil
            }
        }
        return result
    }

    static func save(question: String, reply: String, actions: [String], in context: ModelContext) {
        let now = Date.now
        context.insert(ChatEntry(isUser: true, text: question, createdAt: now))
        context.insert(ChatEntry(isUser: false, text: reply, actions: actions, createdAt: now.addingTimeInterval(0.001)))

        let entries = all(in: context)
        if entries.count > limit {
            entries.prefix(entries.count - limit).forEach { context.delete($0) }
        }
        try? context.save()
    }

    static func clear(in context: ModelContext) {
        all(in: context).forEach { context.delete($0) }
        try? context.save()
    }
}

/// Просьбы «открой разговор и слушай» — от Siri, кнопки «Действие» и виджета.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    /// Новая просьба поговорить. Экран разговора её «забирает» и включает микрофон.
    var talkRequest: UUID?

    func requestTalk() {
        talkRequest = UUID()
    }

    func consumeTalkRequest() -> Bool {
        guard talkRequest != nil else { return false }
        talkRequest = nil
        return true
    }
}
