import Foundation
import Speech
import AVFoundation
import Observation

/// Превращает голос в текст с помощью встроенного распознавания речи Apple.
/// Если iPhone умеет распознавать русский без интернета — делает это прямо на устройстве.
@MainActor
@Observable
final class SpeechRecognizer {
    enum State: Equatable {
        case idle
        case recording
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    var problem: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isRecording: Bool { state == .recording }

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        problem = nil
        guard await Self.requestPermissions() else {
            problem = "Чтобы слушать тебя, нужен доступ к микрофону и распознаванию речи. Включи его в Настройках iPhone → Offload."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "Распознавание речи сейчас недоступно. Можно пока написать текстом."
            return
        }

        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let engine = AVAudioEngine()
            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            let recordingID = ObjectIdentifier(request)
            self.task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    // Игнорируем «опоздавшие» ответы от прошлой записи.
                    guard let self, let current = self.request, ObjectIdentifier(current) == recordingID else { return }
                    if let text { self.transcript = text }
                    if finished { self.finish() }
                }
            }
            state = .recording
        } catch {
            problem = "Не получилось включить микрофон. Попробуй ещё раз."
            finish()
        }
    }

    /// Останавливает запись. Распознавание успеет дописать последние слова.
    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        state = .idle
    }

    private func finish() {
        stop()
        task = nil
        request = nil
        engine = nil
        // Если приложение уже отвечает голосом — не выключаем звук.
        if !VoiceService.shared.isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // Эти функции работают вне главного потока: звук приходит из фоновой очереди.

    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            onUpdate(text, error != nil || result?.isFinal == true)
        }
    }

    nonisolated private static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
