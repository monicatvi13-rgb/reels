import Foundation
import AVFoundation
import Observation

/// Голос приложения: встроенная озвучка iPhone.
/// Бесплатно, без интернета и одинаково работает с любой нейросетью.
@MainActor
@Observable
final class VoiceService: NSObject {
    static let shared = VoiceService()

    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

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
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
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
        guard !synthesizer.isSpeaking else { return }
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
