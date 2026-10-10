import Foundation
import AVFoundation
import Observation

/// Голос приложения. Два варианта:
/// - Apple — встроенная озвучка iPhone: бесплатно и без интернета;
/// - «живой» — нейросетевой голос Яндекса, если подключён ключ.
/// Если Яндекс недоступен, приложение тут же говорит голосом Apple.
@MainActor
@Observable
final class VoiceService: NSObject {
    static let shared = VoiceService()

    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Все русские голоса на устройстве: лучшие — первыми.
    static var russianVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func displayName(of voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "\(voice.name) · премиум"
        case .enhanced: "\(voice.name) · улучшенный"
        default: voice.name
        }
    }

    /// Произносит текст, если голос включён в настройках (или если попросили явно).
    func speak(_ text: String, force: Bool = false) {
        guard force || AppSettings.voiceEnabled else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Пока идёт запись, не перебиваем микрофон.
        guard !SpeechRecognizer.isAnyRecording else { return }

        stop()

        if AppSettings.voiceEngine == .yandex, let key = YandexSpeech.apiKey {
            isSpeaking = true
            let voice = AppSettings.yandexVoice
            speakTask = Task { [weak self] in
                do {
                    let audio = try await YandexSpeech.synthesize(clean, voice: voice, apiKey: key)
                    guard !Task.isCancelled else { return }
                    self?.play(audio)
                } catch {
                    // Яндекс не ответил — не молчим, говорим голосом Apple.
                    guard !Task.isCancelled else { return }
                    self?.speakWithApple(clean)
                }
            }
        } else {
            speakWithApple(clean)
        }
    }

    /// Последняя ошибка «живого» голоса — показывается в настройках при проверке.
    private(set) var lastYandexError: String?

    /// Проверка «живого» голоса из настроек: говорит фразу и запоминает ошибку, если она была.
    func testYandex(_ text: String) async {
        stop()
        lastYandexError = nil
        guard let key = YandexSpeech.apiKey else {
            lastYandexError = "Сначала сохрани ключ Яндекса."
            return
        }
        isSpeaking = true
        do {
            let audio = try await YandexSpeech.synthesize(text, voice: AppSettings.yandexVoice, apiKey: key)
            play(audio)
        } catch {
            isSpeaking = false
            lastYandexError = error.localizedDescription
        }
    }

    private func activatePlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func play(_ audio: Data) {
        guard !SpeechRecognizer.isAnyRecording else {
            isSpeaking = false
            return
        }
        activatePlayback()
        do {
            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            self.player = player
            isSpeaking = true
            player.play()
        } catch {
            isSpeaking = false
        }
    }

    private func speakWithApple(_ clean: String) {
        guard !SpeechRecognizer.isAnyRecording else {
            isSpeaking = false
            return
        }
        activatePlayback()

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private static var selectedVoice: AVSpeechSynthesisVoice? {
        let id = AppSettings.voiceIdentifier
        if !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return russianVoices.first ?? AVSpeechSynthesisVoice(language: "ru-RU")
    }

    private func finished() {
        // Отмена старой фразы не должна обрывать новую.
        guard !synthesizer.isSpeaking, !(player?.isPlaying ?? false) else { return }
        player = nil
        isSpeaking = false
        // Микрофон уже включён — звук не выключаем, иначе запись оборвётся.
        guard !SpeechRecognizer.isAnyRecording else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in VoiceService.shared.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in VoiceService.shared.finished() }
    }
}

extension VoiceService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in VoiceService.shared.finished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in VoiceService.shared.finished() }
    }
}
