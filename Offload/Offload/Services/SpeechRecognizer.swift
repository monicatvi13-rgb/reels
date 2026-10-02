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

    /// Идёт ли сейчас запись где-нибудь в приложении — чтобы голос не выключил микрофон.
    static private(set) var isAnyRecording = false

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
        // Приложение говорит — замолкаем, чтобы не мешать микрофону.
        VoiceService.shared.stop()

        guard await Self.requestPermissions() else {
            problem = "Чтобы слушать тебя, нужен доступ к микрофону и распознаванию речи. Включи его в Настройках iPhone → Offload."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "Распознавание речи сейчас недоступно. Проверь интернет или напиши текстом."
            return
        }

        transcript = ""
        do {
            // Те же настройки звука, что в первой версии, где запись точно работала.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            #if targetEnvironment(simulator)
            // В симуляторе распознавание без интернета часто не работает.
            request.requiresOnDeviceRecognition = false
            #else
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            #endif

            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                problem = Self.noMicrophoneHint
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            Self.installTap(on: engine.inputNode, format: format, feeding: request)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            let recordingID = ObjectIdentifier(request)
            self.task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, finished, errorCode in
                Task { @MainActor in
                    // Игнорируем «опоздавшие» ответы от прошлой записи.
                    guard let self, let current = self.request, ObjectIdentifier(current) == recordingID else { return }
                    if let text { self.transcript = text }
                    if let errorCode, self.transcript.isEmpty, self.isRecording {
                        // Запись оборвалась, не успев ничего услышать, — говорим об этом прямо.
                        self.problem = "Не получилось распознать речь (код \(errorCode)). Попробуй ещё раз или напиши текстом."
                    }
                    if finished { self.finish() }
                }
            }
            state = .recording
            Self.isAnyRecording = true
        } catch {
            problem = "Не получилось включить микрофон (\((error as NSError).code)). Попробуй ещё раз."
            finish()
        }
    }

    /// Останавливает запись. Распознавание успеет дописать последние слова.
    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        state = .idle
        Self.isAnyRecording = false
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

    private static var noMicrophoneHint: String {
        #if targetEnvironment(simulator)
        "Симулятор не слышит микрофон Mac. Разреши доступ: Настройки Mac → Конфиденциальность и безопасность → Микрофон → включи Xcode и Simulator. Или проверь на iPhone."
        #else
        "Микрофон сейчас недоступен. Закрой приложения, которые могут его занимать (звонок, диктофон), и попробуй ещё раз."
        #endif
    }

    // Эти функции работают вне главного потока: звук приходит из фоновой очереди.

    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool, Int?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let code = error.map { ($0 as NSError).code }
            onUpdate(text, error != nil || result?.isFinal == true, code)
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
