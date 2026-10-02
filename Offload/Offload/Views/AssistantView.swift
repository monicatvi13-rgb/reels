import SwiftUI
import SwiftData

/// Экран-собеседник: спроси голосом или текстом — Offload ответит голосом.
struct AssistantView: View {
    @Query(sort: \OffloadItem.createdAt, order: .reverse) private var items: [OffloadItem]
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.Key.voiceEnabled) private var voiceEnabled = true

    @State private var speech = SpeechRecognizer()
    @State private var voice = VoiceService.shared
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isCapturingSpeech = false
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Что у меня сегодня?",
        "Что на завтра?",
        "Что на этой неделе?",
        "Что нужно купить?",
        "Какие у меня идеи?",
        "Напомни завтра в 10 позвонить маме",
        "Добавь в покупки молоко и хлеб"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty {
                                welcome
                            }
                            ForEach(messages) { message in
                                MessageBubble(message: message) {
                                    voice.speak(message.text, force: true)
                                }
                                .id(message.id)
                            }
                            if isThinking {
                                ThinkingBubble()
                                    .id("thinking")
                            }
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        if let id = messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: isThinking) { _, thinking in
                        if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                }

                if speech.isRecording {
                    LevelMeter(level: speech.level)
                        .padding(.top, 6)
                }

                if let problem = speech.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                inputBar
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Спросить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        voiceEnabled.toggle()
                        if !voiceEnabled { voice.stop() }
                    } label: {
                        Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundStyle(voiceEnabled ? Theme.accent : Theme.muted)
                    }
                    .accessibilityLabel(voiceEnabled ? "Выключить голос" : "Включить голос")
                }
            }
            .onChange(of: speech.transcript) { _, newValue in
                guard isCapturingSpeech else { return }
                input = newValue
            }
        }
    }

    // MARK: - Приветствие

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Спроси меня")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("О делах, планах и покупках. Отвечу голосом — можно не смотреть в экран.")
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 12)

            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { send(suggestion) }
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.card, in: Capsule())
                }
            }
        }
    }

    // MARK: - Нижняя панель

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(speech.isRecording ? "Слушаю…" : "Спроси что угодно…", text: $input)
                .focused($inputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .submitLabel(.send)
                .onSubmit { send(input) }

            if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !speech.isRecording {
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Theme.accent, in: Circle())
                }
                .accessibilityLabel("Отправить")
            } else {
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(speech.isRecording ? Theme.recording : Theme.accent, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(speech.isRecording ? "Остановить и спросить" : "Спросить голосом")
                .sensoryFeedback(.impact(weight: .medium), trigger: speech.isRecording)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
        .disabled(isThinking)
    }

    // MARK: - Действия

    private func toggleRecording() async {
        inputFocused = false
        if speech.isRecording {
            speech.stop()
            // Даём распознаванию дописать последние слова.
            try? await Task.sleep(for: .milliseconds(700))
            isCapturingSpeech = false
            send(input)
        } else {
            voice.stop()
            input = ""
            isCapturingSpeech = true
            await speech.start()
            if !speech.isRecording {
                // Нет доступа к микрофону — подсказка уже на экране.
                isCapturingSpeech = false
            }
        }
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        isCapturingSpeech = false
        inputFocused = false
        input = ""
        voice.stop()

        let history = turns()
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true

        // Снимок списков: номер пункта в нём — его id для нейросети.
        let current = Array(items)
        let snapshot = current.map { ItemSnapshot($0) }
        Task {
            let reply = await Assistant().respond(to: question, items: snapshot, history: history)
            let done = ActionRunner(context: context).run(reply.actions, on: current)
            isThinking = false
            messages.append(ChatMessage(role: .assistant, text: reply.text, actions: done))
            voice.speak(reply.text)
        }
    }

    /// Прошлые вопросы и ответы — чтобы собеседник помнил контекст разговора.
    private func turns() -> [Assistant.Turn] {
        var result: [Assistant.Turn] = []
        var pendingQuestion: String?
        for message in messages {
            switch message.role {
            case .user: pendingQuestion = message.text
            case .assistant:
                if let question = pendingQuestion {
                    result.append(Assistant.Turn(question: question, answer: message.text))
                    pendingQuestion = nil
                }
            }
        }
        return result
    }
}

// MARK: - Сообщения

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
    /// Что сделано по команде: «＋ Позвонить маме · завтра, 10:00».
    var actions: [String] = []
}

private struct MessageBubble: View {
    let message: ChatMessage
    let onReplay: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .foregroundStyle(message.role == .user ? .white : Theme.ink)
                    .textSelection(.enabled)

                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                            Text(action)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                message.role == .user ? Theme.accent : Theme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )

            if message.role == .assistant {
                Button(action: onReplay) {
                    Image(systemName: "speaker.wave.2")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(6)
                }
                .accessibilityLabel("Прослушать ещё раз")
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ThinkingBubble: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Theme.muted)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([0.3, 1.0]) { dot, opacity in
                        dot.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Думаю")
    }
}

/// Раскладывает подсказки «плиткой»: сколько влезает в строку, остальные — ниже.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    AssistantView()
        .modelContainer(for: [BrainDump.self, OffloadItem.self], inMemory: true)
}
