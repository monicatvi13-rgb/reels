import Foundation
import AVFoundation
import Observation

/// Голос приложения: встроенная озвучка Apple — бесплатно, без интернета и без настроек.
/// Чтобы звучать живее, текст делится на фразы с естественными паузами,
/// а перед озвучкой убирается всё, на чём голос спотыкается.
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

    // MARK: - Голоса

    /// Все русские голоса на устройстве: лучшие — первыми.
    static var russianVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    /// Есть ли на устройстве «улучшенный» или «премиум» русский голос.
    static var hasHighQualityVoice: Bool {
        russianVoices.contains { $0.quality != .default }
    }

    static func displayName(of voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "\(voice.name) · премиум"
        case .enhanced: "\(voice.name) · улучшенный"
        default: voice.name
        }
    }

    private static var selectedVoice: AVSpeechSynthesisVoice? {
        let id = AppSettings.voiceIdentifier
        if !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return russianVoices.first ?? AVSpeechSynthesisVoice(language: "ru-RU")
    }

    // MARK: - Речь

    /// Произносит текст, если голос включён в настройках (или если попросили явно).
    func speak(_ text: String, force: Bool = false) {
        guard force || AppSettings.voiceEnabled else { return }
        let phrases = Self.phrases(from: Self.prepare(text))
        guard !phrases.isEmpty else { return }

        // Пока идёт запись, не перебиваем микрофон.
        guard !SpeechRecognizer.isAnyRecording else { return }

        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        let voice = Self.selectedVoice
        let pace = AppSettings.speechPace
        isSpeaking = true

        for (index, phrase) in phrases.enumerated() {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            utterance.rate = pace.rate
            utterance.pitchMultiplier = 1.0
            // Короткая пауза между фразами — как человек делает вдох.
            utterance.postUtteranceDelay = index == phrases.count - 1 ? 0 : Self.pause(after: phrase)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func finished() {
        // Ещё есть фразы в очереди или уже говорим новую — ничего не выключаем.
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        // Микрофон уже включён — звук не выключаем, иначе запись оборвётся.
        guard !SpeechRecognizer.isAnyRecording else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Подготовка текста

    /// Убирает то, что голос читает вслух или на чём спотыкается.
    static func prepare(_ text: String) -> String {
        var result = text
        // Эмодзи и прочие пиктограммы.
        result = String(String.UnicodeScalarView(result.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C))
        }))

        let replacements: [(String, String)] = [
            ("**", ""), ("__", ""), ("#", ""), ("`", ""), ("*", ""),
            ("•", ""), ("→", ","), ("—", ","), ("–", ","),
            ("₽", " рублей"), ("%", " процентов"),
            ("и т.д.", "и так далее"), ("т.е.", "то есть"), ("т.к.", "так как"),
            ("«", ""), ("»", ""), ("\"", "")
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        // Маркеры списков в начале строк: «1.», «-».
        result = result.replacingOccurrences(of: #"(?m)^\s*(\d+[.)]|-)\s+"#, with: "", options: .regularExpression)
        // Лишние запятые подряд и пробелы.
        result = result.replacingOccurrences(of: #"\s*,(\s*,)+"#, with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Делит текст на фразы: по предложениям и строкам.
    static func phrases(from text: String) -> [String] {
        var phrases: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sentence, _, _, _ in
            guard let sentence else { return }
            for line in sentence.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty { phrases.append(clean) }
            }
        }
        return phrases.isEmpty && !text.isEmpty ? [text] : phrases
    }

    /// После вопроса и восклицания пауза чуть длиннее — так звучит естественнее.
    private static func pause(after phrase: String) -> TimeInterval {
        switch phrase.last {
        case "?", "!": 0.35
        case ".", "…": 0.28
        default: 0.18
        }
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
