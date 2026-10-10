import SwiftUI

/// Пошаговая инструкция: как получить ключ для «живого» голоса Яндекса.
struct YandexGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id = UUID()
        let title: String
        let text: String
        var link: URL?
    }

    private let steps: [Step] = [
        Step(title: "Открой Яндекс Облако",
             text: "Войди через Яндекс ID — тот же, что для Почты или Диска.",
             link: URL(string: "https://console.yandex.cloud")),
        Step(title: "Создай платёжный аккаунт",
             text: "Привяжи российскую карту. Новым пользователям Яндекс обычно даёт стартовый бонус — его хватит надолго."),
        Step(title: "Создай сервисный аккаунт",
             text: "В каталоге default открой «Сервисные аккаунты» → «Создать». Имя — например, offload. Роль — ai.speechkit-tts.user."),
        Step(title: "Создай API-ключ",
             text: "Открой созданный сервисный аккаунт → «Создать новый ключ» → «Создать API-ключ». Если спросят область действия — выбери SpeechKit TTS. Скопируй секретный ключ: он показывается один раз."),
        Step(title: "Вставь ключ в Offload",
             text: "Настройки → Голос → «Живой · Яндекс» → вставь ключ → «Сохранить ключ» → «Послушать».")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Платно, но недорого")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Около 1 342 ₽ за миллион символов — это примерно 0,2 ₽ за один ответ. Двадцать ответов в день — около 120 ₽ в месяц. Цена указана Яндексом в долларах, поэтому в рублях зависит от курса.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .card()

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(index + 1)")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.accent, in: Circle())

                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.title)
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Text(step.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let link = step.link {
                                    Link(destination: link) {
                                        Label("Открыть сайт", systemImage: "arrow.up.right")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .card()
                    }

                    Label("Названия кнопок в Яндекс Облаке могут немного отличаться — интерфейс иногда меняется.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Живой голос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    YandexGuideView()
}
