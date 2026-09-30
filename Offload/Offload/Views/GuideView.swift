import SwiftUI

/// Пошаговая инструкция: как подключить нейросеть и сколько это стоит.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var provider: AIProvider
    @State private var key = ""
    @State private var saved = false

    init(initial: AIProvider = .current) {
        _provider = State(initialValue: initial)
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Offload думает с помощью нейросети. Выбери, какую подключить — всё остальное работает одинаково.")
                        .foregroundStyle(Theme.muted)

                    Picker("Нейросеть", selection: $provider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    priceCard

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        StepCard(number: index + 1, title: step.title, text: step.text, link: step.link)
                    }

                    keyCard

                    if let note {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Как подключить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onChange(of: provider) { _, _ in
                key = ""
                saved = false
            }
        }
    }

    // MARK: - Карточки

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider == .gigachat ? "Бесплатно" : "Платно")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if provider == .gigachat {
                    Text("Советуем")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: Capsule())
                }
            }
            Text(priceText)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Вставь \(provider.keyName.lowercased()) сюда")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            SecureField(provider.keyPlaceholder, text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(14)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                guard !trimmedKey.isEmpty else { dismiss(); return }
                provider.saveKey(trimmedKey)
                AIProvider.current = provider
                key = ""
                withAnimation { saved = true }
            } label: {
                Label(saved ? "Готово! Можно выгружать мысли" : "Сохранить и подключить",
                      systemImage: saved ? "checkmark" : "bolt.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedKey.isEmpty && !saved)
            .sensoryFeedback(.success, trigger: saved)

            Text("Ключ хранится только в защищённом хранилище этого iPhone и никому не передаётся, кроме самой нейросети.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: - Тексты

    private var priceText: String {
        switch provider {
        case .gigachat:
            "Сбер даёт физическим лицам бесплатный лимит на год — его с большим запасом хватит на ежедневные «сливы». Карта не нужна, работает в России."
        case .claude:
            "Нужно пополнить баланс в Anthropic — от $5, иностранной картой. Это не подписка: деньги списываются понемногу за каждый разбор и сгорают через год. Claude недоступен в России."
        }
    }

    private var note: String? {
        switch provider {
        case .gigachat:
            "Названия кнопок на сайте Сбера могут немного отличаться — Сбер иногда обновляет интерфейс."
        case .claude:
            nil
        }
    }

    private struct Step {
        let title: String
        let text: String
        var link: URL?
    }

    private var steps: [Step] {
        switch provider {
        case .gigachat:
            [
                Step(title: "Открой сайт Сбера для разработчиков",
                     text: "И войди через Сбер ID — так же, как в СберБанк Онлайн.",
                     link: URL(string: "https://developers.sber.ru/studio")),
                Step(title: "Создай проект GigaChat API",
                     text: "В личном пространстве нажми «Создать проект» и выбери GigaChat API. Прими условия для физических лиц."),
                Step(title: "Получи ключ авторизации",
                     text: "В настройках проекта нажми «Получить ключ» и скопируй «Ключ авторизации». Он показывается один раз — если потеряешь, просто создай новый."),
                Step(title: "Вставь ключ ниже",
                     text: "И нажми «Сохранить и подключить». Всё!")
            ]
        case .claude:
            [
                Step(title: "Открой консоль Anthropic",
                     text: "Зарегистрируйся — можно через Google.",
                     link: URL(string: "https://console.anthropic.com")),
                Step(title: "Пополни баланс",
                     text: "Settings → Billing → Buy credits. Для начала хватит $5 — это примерно несколько сотен разборов."),
                Step(title: "Создай ключ",
                     text: "Settings → API Keys → Create Key. Скопируй ключ, он начинается с sk-ant- и показывается один раз.",
                     link: URL(string: "https://console.anthropic.com/settings/keys")),
                Step(title: "Вставь ключ ниже",
                     text: "И нажми «Сохранить и подключить».")
            ]
        }
    }
}

/// Карточка одного шага инструкции.
private struct StepCard: View {
    let number: Int
    let title: String
    let text: String
    let link: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Link(destination: link) {
                        Label("Открыть сайт", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .card()
    }
}

#Preview {
    GuideView()
}
