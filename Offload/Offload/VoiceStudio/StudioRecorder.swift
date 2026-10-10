import Foundation
import AVFoundation
import Observation

/// Записывает голос для обучения нейросети: каждое предложение — отдельный WAV-файл.
/// Файлы лежат в папке приложения VoiceDataset и выгружаются одним архивом.
@MainActor
@Observable
final class StudioRecorder: NSObject {
    enum State { case idle, recording, playing }

    private(set) var state: State = .idle
    /// Громкость от 0 до 1 — для индикатора.
    private(set) var level: Float = 0
    var problem: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private var peakLevel: Float = 0

    // MARK: - Предложения и файлы

    /// Тексты для записи: файл sentences.txt, по одному предложению в строке.
    static let sentences: [String] = {
        guard let url = Bundle.main.url(forResource: "sentences", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }()

    static var datasetFolder: URL {
        URL.documentsDirectory.appending(path: "VoiceDataset", directoryHint: .isDirectory)
    }

    static var wavsFolder: URL {
        datasetFolder.appending(path: "wavs", directoryHint: .isDirectory)
    }

    static func fileName(for index: Int) -> String {
        String(format: "offload_%04d", index + 1)
    }

    static func fileURL(for index: Int) -> URL {
        wavsFolder.appending(path: fileName(for: index) + ".wav")
    }

    static func isRecorded(_ index: Int) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(for: index).path)[.size] as? Int) ?? 0
        return size > 8_000
    }

    static var recordedCount: Int {
        sentences.indices.filter(isRecorded).count
    }

    // MARK: - Запись

    func startRecording(_ index: Int) async {
        problem = nil
        stopPlaying()
        VoiceService.shared.stop()

        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Нужен доступ к микрофону: Настройки → Конфиденциальность → Микрофон."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            try FileManager.default.createDirectory(at: Self.wavsFolder, withIntermediateDirectories: true)

            // WAV, 44,1 кГц, моно, 16 бит — стандарт для обучения голоса.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: Self.fileURL(for: index), settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                problem = "Не получилось начать запись. Проверь микрофон."
                return
            }
            self.recorder = recorder
            peakLevel = 0
            state = .recording
            startMetering()
        } catch {
            problem = "Не получилось начать запись: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        recorder?.stop()
        recorder = nil
        meterTask?.cancel()
        meterTask = nil
        level = 0
        state = .idle
        if peakLevel < 0.15 {
            problem = "Запись получилась очень тихой. Проверь, что выбран нужный микрофон, и говори чуть громче."
        }
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                // Децибелы от −60 до 0 превращаем в шкалу от 0 до 1.
                let power = recorder.averagePower(forChannel: 0)
                let value = max(0, min(1, (power + 60) / 60))
                self.level = value
                self.peakLevel = max(self.peakLevel, value)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    // MARK: - Прослушивание

    func play(_ index: Int) {
        guard Self.isRecorded(index) else { return }
        stopPlaying()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: Self.fileURL(for: index))
            player.delegate = self
            self.player = player
            player.play()
            state = .playing
        } catch {
            problem = "Не получилось воспроизвести запись."
        }
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        if state == .playing { state = .idle }
    }

    fileprivate func playbackFinished() {
        player = nil
        if state == .playing { state = .idle }
    }

    // MARK: - Выгрузка

    /// Собирает архив: папка wavs с записями и metadata.csv в формате «имя|текст».
    static func exportArchive() throws -> URL {
        let recorded = sentences.indices.filter(isRecorded)
        let metadata = recorded
            .map { "\(fileName(for: $0))|\(sentences[$0])" }
            .joined(separator: "\n")
        try FileManager.default.createDirectory(at: datasetFolder, withIntermediateDirectories: true)
        try metadata.write(to: datasetFolder.appending(path: "metadata.csv"), atomically: true, encoding: .utf8)

        let destination = FileManager.default.temporaryDirectory.appending(path: "OffloadVoice.zip")
        try? FileManager.default.removeItem(at: destination)

        var coordinatorError: NSError?
        var copyError: Error?
        // Системный способ упаковать папку в ZIP без сторонних библиотек.
        NSFileCoordinator().coordinate(readingItemAt: datasetFolder, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return destination
    }
}

extension StudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.playbackFinished() }
    }
}
