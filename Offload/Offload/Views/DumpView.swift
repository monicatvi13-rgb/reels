import SwiftUI
import SwiftData

/// Главный экран: наговорить или написать всё, что в голове, и отдать Claude на разбор.
struct DumpView: View {
    @Binding var tab: AppTab

    @Environment(\.modelContext) private var context
    @State private var speech = SpeechRecognizer()

    @State private var text = ""
    @State private var textBeforeRecording = ""
    @State private var isCapturingSpeech = false
    @State private var isSorting = false
    @State private var summary: Summary?
    @State private var errorText: String?
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var hasKey = AIProvider.current.apiKey != nil
    @FocusState private var editorFocused: Bool

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if !hasKey { keyHint }

                    if let summary {
                        SummaryCard(summary: summary) {
                            tab = .lists
                        } onAgain: {
                            withAnimation { self.summary = nil }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    editor
                    micButton
                    sortButton

                    if let problem = speech.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Как подключить нейросеть")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: refreshKeyState) {
                SettingsView()
            }
            .sheet(isPresented: $showGuide, onDismiss: refreshKeyState) {
                GuideView()
            }
            .alert("Что-то пошло не так", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onChange(of: speech.transcript) { _, newValue in
                guard isCapturingSpeech else { return }
                text = textBeforeRecording + newValue
            }
            .sensoryFeedback(.success, trigger: summary?.id)
        }
    }

    // MARK: - Части экрана

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что крутится\nв голове?")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Говори как есть, вперемешку. Я разложу по полочкам.")
                .font(.body)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    private var keyHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Осталось подключить нейросеть", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Это бесплатно и займёт пару минут. Без неё я смогу слушать, но не смогу раскладывать мысли по полочкам.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Button("Как подключить") { showGuide = true }
                .font(.subheadline.weight(.semibold))
        }
        .card()
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Например: завтра к стоматологу в 10, купить молоко и корм коту, придумать тему для рилса, в пятницу у мамы день рождения…")
                    .foregroundStyle(Theme.muted.opacity(0.8))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 180)
        }
        .font(.body)
        .card()
    }

    private var micButton: some View {
        VStack(spacing: 12) {
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    if speech.isRecording {
                        Circle()
                            .stroke(Theme.recording, lineWidth: 6)
                            .phaseAnimator([false, true]) { ring, expanded in
                                ring
                                    .scaleEffect(expanded ? 1.35 : 1)
                                    .opacity(expanded ? 0 : 0.7)
                            } animation: { expanded in
                                expanded ? .easeOut(duration: 1.4) : .linear(duration: 0)
                            }
                    }
                    Circle()
                        .fill(speech.isRecording ? Theme.recording : Theme.accent)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 112, height: 112)
            }
            .buttonStyle(.plain)
            .disabled(isSorting)
            .accessibilityLabel(speech.isRecording ? "Остановить запись" : "Начать запись")
            .sensoryFeedback(.impact(weight: .medium), trigger: speech.isRecording)

            if speech.isRecording {
                LevelMeter(level: speech.level)
            }

            Text(speech.isRecording ? "Слушаю… Нажми, когда закончишь" : "Нажми и говори")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .animation(.default, value: speech.isRecording)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var sortButton: some View {
        Button {
            Task { await sortThoughts() }
        } label: {
            if isSorting {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Раскладываю по полочкам…")
                }
            } else {
                Label("Разложить по полочкам", systemImage: "sparkles")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(trimmedText.isEmpty || isSorting)
    }

    // MARK: - Действия

    private func refreshKeyState() {
        hasKey = AIProvider.current.apiKey != nil
    }

    private func toggleRecording() async {
        editorFocused = false
        if !speech.isRecording {
            textBeforeRecording = trimmedText.isEmpty ? "" : trimmedText + " "
            isCapturingSpeech = true
        }
        await speech.toggle()
    }

    private func sortThoughts() async {
        if speech.isRecording { speech.stop() }
        isCapturingSpeech = false
        editorFocused = false

        let input = trimmedText
        guard !input.isEmpty else { return }

        isSorting = true
        defer { isSorting = false }

        do {
            let sorted = try await ThoughtSorter().sort(input)
            save(sorted, from: input)
            withAnimation(.spring(duration: 0.5)) {
                summary = Summary(sorted)
                text = ""
            }
            if !sorted.comment.isEmpty {
                VoiceService.shared.speak(sorted.comment)
            }
        } catch AIError.noKey {
            showGuide = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save(_ sorted: SortedThoughts, from input: String) {
        let dump = BrainDump(text: input, comment: sorted.comment)
        context.insert(dump)

        let groups: [(ItemCategory, [SortedThoughts.Entry])] = [
            (.urgent, sorted.urgent),
            (.dated, sorted.dated),
            (.ideas, sorted.ideas),
            (.home, sorted.home)
        ]
        for (category, entries) in groups {
            for entry in entries {
                let due = ThoughtSorter.parseDue(date: entry.date, time: entry.time)
                let item = OffloadItem(
                    title: entry.title,
                    category: category,
                    dueDate: due.date,
                    hasTime: due.hasTime
                )
                item.dump = dump
                context.insert(item)
            }
        }
        try? context.save()
    }
}

// MARK: - Итог разбора

struct Summary: Identifiable {
    let id = UUID()
    let comment: String
    let counts: [CategoryCount]
    let total: Int

    struct CategoryCount {
        let category: ItemCategory
        let count: Int
    }

    init(_ sorted: SortedThoughts) {
        comment = sorted.comment
        total = sorted.count
        counts = [
            CategoryCount(category: .urgent, count: sorted.urgent.count),
            CategoryCount(category: .dated, count: sorted.dated.count),
            CategoryCount(category: .ideas, count: sorted.ideas.count),
            CategoryCount(category: .home, count: sorted.home.count)
        ].filter { $0.count > 0 }
    }
}

private struct SummaryCard: View {
    let summary: Summary
    let onOpenLists: () -> Void
    let onAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if summary.total == 0 {
                Text("Здесь не нашлось дел или идей. Попробуй рассказать чуть подробнее.")
                    .foregroundStyle(Theme.ink)
            } else {
                Text(summary.comment)
                    .font(.system(.title3, design: .serif).italic())
                    .foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.counts, id: \.category) { row in
                        HStack(spacing: 12) {
                            Image(systemName: row.category.symbol)
                                .frame(width: 24)
                                .foregroundStyle(Theme.accent)
                            Text(row.category.title)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(row.count)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }

                Button("Открыть списки", action: onOpenLists)
                    .buttonStyle(PrimaryButtonStyle())
            }

            Button("Выгрузить ещё", action: onAgain)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
        .card()
    }
}

#Preview {
    DumpView(tab: .constant(.dump))
        .modelContainer(for: [BrainDump.self, OffloadItem.self], inMemory: true)
}
