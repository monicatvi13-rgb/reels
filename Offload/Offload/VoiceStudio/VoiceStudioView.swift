import SwiftUI

/// «Студия голоса»: запись предложений для обучения нейросети говорить твоим голосом.
struct VoiceStudioView: View {
    @AppStorage("studioIndex") private var index = 0
    @State private var recorder = StudioRecorder()
    @State private var recordedCount = StudioRecorder.recordedCount
    @State private var currentRecorded = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false

    private let sentences = StudioRecorder.sentences

    private var safeIndex: Int { min(max(index, 0), max(sentences.count - 1, 0)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sentences.isEmpty {
                    Text("Не нашёлся файл с текстами sentences.txt. Проверь, что он лежит в папке VoiceStudio.")
                        .foregroundStyle(Theme.recording)
                } else {
                    progress
                    tips
                    sentenceCard
                    recordControls
                    navigation
                    exportSection
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Студия голоса")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: index) { _, _ in
            recorder.stopPlaying()
            recorder.problem = nil
            refresh()
        }
        .onDisappear {
            recorder.stopRecording()
            recorder.stopPlaying()
        }
    }

    // MARK: - Части экрана

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Записано \(recordedCount) из \(sentences.count)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("≈ \(minutesRecorded) мин")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: Double(recordedCount), total: Double(max(sentences.count, 1)))
                .tint(Theme.accent)
        }
        .card()
    }

    /// Примерно 5 секунд на предложение.
    private var minutesRecorded: Int { recordedCount * 5 / 60 }

    private var tips: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                tip("🤫", "Тихая комната: закрой окно, выключи вентилятор и музыку.")
                tip("📏", "Одно и то же расстояние до микрофона — 20–30 см, каждый раз.")
                tip("🗣", "Говори естественно, как в разговоре с подругой, не «дикторским» голосом.")
                tip("⏸", "Нажми «Запись», подожди полсекунды, прочитай, подожди полсекунды, нажми «Стоп».")
                tip("🔁", "Оговорилась или кашлянула — просто перезапиши.")
                tip("💧", "Не больше 30–40 минут подряд, пей воду. Голос должен быть свежим.")
                tip("⌨️", "На Mac: пробел — запись и стоп, стрелки — назад и вперёд.")
            }
            .padding(.top, 8)
        } label: {
            Label("Как записывать, чтобы голос получился живым", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .card()
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Фраза \(safeIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if currentRecorded {
                    Label("Записано", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(sentences[safeIndex])
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .card()
    }

    private var recordControls: some View {
        VStack(spacing: 14) {
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.state == .recording ? Theme.recording : Theme.accent)
                    Image(systemName: recorder.state == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 96, height: 96)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(recorder.state == .recording ? "Стоп" : "Запись")

            if recorder.state == .recording {
                LevelMeter(level: recorder.level)
                Text("Идёт запись… Прочитай фразу и нажми «Стоп»")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                Text(currentRecorded ? "Можно прослушать или перезаписать" : "Нажми и прочитай фразу")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            if let problem = recorder.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.recording)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button {
                index = max(safeIndex - 1, 0)
            } label: {
                Label("Назад", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(safeIndex == 0 || recorder.state == .recording)

            Button {
                if recorder.state == .playing {
                    recorder.stopPlaying()
                } else {
                    recorder.play(safeIndex)
                }
            } label: {
                Label(recorder.state == .playing ? "Стоп" : "Слушать",
                      systemImage: recorder.state == .playing ? "stop.circle" : "play.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!currentRecorded || recorder.state == .recording)

            Button {
                index = min(safeIndex + 1, sentences.count - 1)
            } label: {
                Label("Дальше", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(safeIndex >= sentences.count - 1 || recorder.state == .recording)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Готовые записи")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Когда запишешь всё (или часть — для пробного обучения), собери архив и сохрани его на Mac. Он понадобится для обучения нейросети.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            Button {
                jumpToNextUnrecorded()
            } label: {
                Label("К следующей незаписанной фразе", systemImage: "forward.end")
            }
            .font(.subheadline.weight(.semibold))
            .disabled(recordedCount == sentences.count)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Сохранить архив OffloadVoice.zip", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    prepareExport()
                } label: {
                    Label(isExporting ? "Собираю архив…" : "Собрать архив", systemImage: "archivebox")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(recordedCount == 0 || isExporting)
            }

            if let exportError {
                Text(exportError)
                    .font(.footnote)
                    .foregroundStyle(Theme.recording)
            }
        }
        .card()
    }

    // MARK: - Действия

    private func toggleRecording() async {
        if recorder.state == .recording {
            recorder.stopRecording()
            refresh()
        } else {
            exportURL = nil
            await recorder.startRecording(safeIndex)
        }
    }

    private func refresh() {
        recordedCount = StudioRecorder.recordedCount
        currentRecorded = StudioRecorder.isRecorded(safeIndex)
    }

    private func jumpToNextUnrecorded() {
        let order = Array(safeIndex..<sentences.count) + Array(0..<safeIndex)
        if let next = order.first(where: { !StudioRecorder.isRecorded($0) }) {
            index = next
        }
    }

    private func prepareExport() {
        isExporting = true
        exportError = nil
        do {
            exportURL = try StudioRecorder.exportArchive()
        } catch {
            exportError = "Не получилось собрать архив: \(error.localizedDescription)"
        }
        isExporting = false
    }
}

#Preview {
    NavigationStack {
        VoiceStudioView()
    }
}
