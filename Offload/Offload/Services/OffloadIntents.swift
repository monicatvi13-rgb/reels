import AppIntents
import SwiftData

/// «Привет, Siri, спроси Offload» — вопрос или команда без открытия приложения.
struct AskOffloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Спросить Offload"
    static let description = IntentDescription("Задай вопрос или дай команду: «что у меня завтра?», «напомни завтра в 10 позвонить маме».")
    static let openAppWhenRun = false

    @Parameter(title: "Вопрос", requestValueDialog: IntentDialog("Что спросить?"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = OffloadStore.container.mainContext
        let descriptor = FetchDescriptor<OffloadItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let items = (try? context.fetch(descriptor)) ?? []

        let history = ChatMemory.turns(from: ChatMemory.all(in: context))
        let reply = await Assistant().respond(to: question, items: items.map { ItemSnapshot($0) }, history: history)
        let done = ActionRunner(context: context).run(reply.actions, on: items)
        ChatMemory.save(question: question, reply: reply.text, actions: done, in: context)

        // Обновляем уведомления и Календарь — приложение может быть закрыто.
        let updated = (try? context.fetch(descriptor)) ?? []
        await AppSync.refresh(updated)

        return .result(dialog: "\(reply.text)")
    }
}

/// «Поговорить с Offload» — открывает разговор, и микрофон сразу слушает.
/// Эту команду удобно повесить на кнопку «Действие».
struct TalkToOffloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Поговорить с Offload"
    static let description = IntentDescription("Открывает разговор с помощником и сразу включает микрофон.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.requestTalk()
        return .result()
    }
}

/// Команды, которые iPhone сам показывает в Siri, «Быстрых командах» и настройках кнопки «Действие».
struct OffloadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskOffloadIntent(),
            phrases: [
                "Спроси \(.applicationName)",
                "Спросить \(.applicationName)",
                "Вопрос \(.applicationName)"
            ],
            shortTitle: "Спросить",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: TalkToOffloadIntent(),
            phrases: [
                "Поговорить с \(.applicationName)",
                "Открой разговор в \(.applicationName)"
            ],
            shortTitle: "Поговорить",
            systemImageName: "mic.fill"
        )
    }
}
