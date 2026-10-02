import SwiftUI
import UIKit
import AVFoundation

/// Настройки: нейросеть, голос, уведомления и Календарь.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Нейросеть
    @State private var provider: AIProvider = .current
    @State private var key = ""
    @State private var hasSavedKey = AIProvider.current.savedKey != nil
    @State private var justSaved = false
    @State private var showGuide = false

    // Голос
    @AppStorage(AppSettings.Key.voiceEnabled) private var voiceEnabled = true
    @AppStorage(AppSettings.Key.voiceIdentifier) private var voiceIdentifier = ""

    // Уведомления
    @AppStorage(AppSettings.Key.morningDigest) private var morningDigest = false
    @AppStorage(AppSettings.Key.digestTime) private var digestTime = AppSettings.defaultDigestTime
    @AppStorage(AppSettings.Key.itemReminders) private var itemReminders = false
    @State private var notificationsDenied = false

    // Календарь
    @AppStorage(AppSettings.Key.calendarMode) private var calendarModeRaw = CalendarMode.none.rawValue
    @State private var calendarDenied = false

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let voices = VoiceService.russianVoices

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                notificationsSection
                calendarSection
                aiSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onChange(of: provider) { _, newValue in
                AIProvider.current = newValue
                key = ""
                justSaved = false
                hasSavedKey = newValue.savedKey != nil
            }
            .sheet(isPresented: $showGuide) {
                GuideView(initial: provider)
            }
        }
    }

    // MARK: - Голос

    private var voiceSection: some View {
        Section {
            Toggle("Отвечать голосом", isOn: $voiceEnabled)

            if voiceEnabled {
                Picker("Голос", selection: $voiceIdentifier) {
                    Text("Лучший доступный").tag("")
                    ForEach(voices, id: \.identifier) { voice in
                        Text(VoiceService.displayName(of: voice)).tag(voice.identifier)
                    }
                }

                Button {
                    VoiceService.shared.speak("Привет! Я Offload. Расскажи, что у тебя в голове, — я всё разложу и напомню.", force: true)
                } label: {
                    Label("Послушать", systemImage: "play.circle")
                }
            }
        } header: {
            Text("Голос")
        } footer: {
            Text("Голос встроен в iPhone: бесплатно и без интернета. Чтобы звучало живее, скачай улучшенный русский голос: Настройки iPhone → Универсальный доступ → Устный контент → Голоса → Русский.")
        }
    }

    // MARK: - Уведомления

    private var notificationsSection: some View {
        Section {
            Toggle("Утренняя сводка", isOn: Binding(
                get: { morningDigest },
                set: { newValue in Task { await setNotification(.morningDigest, to: newValue) } }
            ))

            if morningDigest {
                DatePicker("Во сколько", selection: Binding(
                    get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(digestTime) },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        digestTime = Double((parts.hour ?? 9) * 3600 + (parts.minute ?? 0) * 60)
                        settingsChanged()
                    }
                ), displayedComponents: .hourAndMinute)
            }

            Toggle("Напоминать о делах со временем", isOn: Binding(
                get: { itemReminders },
                set: { newValue in Task { await setNotification(.itemReminders, to: newValue) } }
            ))

            if notificationsDenied {
                Button("Разрешить уведомления в Настройках iPhone") { openSettings() }
            }
        } header: {
            Text("Уведомления")
        } footer: {
            Text("Утром — короткая сводка дел на день. Перед делами, у которых указано время, — напоминание за 15 минут. Всё приходит на заблокированный экран.")
        }
    }

    private enum NotificationToggle { case morningDigest, itemReminders }

    /// Включает уведомление. При первом включении iPhone спросит разрешение.
    private func setNotification(_ toggle: NotificationToggle, to enabled: Bool) async {
        notificationsDenied = false
        if enabled {
            var allowed = await NotificationScheduler.isAuthorized()
            if !allowed { allowed = await NotificationScheduler.requestPermission() }
            guard allowed else {
                notificationsDenied = true
                return
            }
        }
        switch toggle {
        case .morningDigest: morningDigest = enabled
        case .itemReminders: itemReminders = enabled
        }
        settingsChanged()
    }

    // MARK: - Календарь

    private var calendarSection: some View {
        Section {
            Picker("Дела с датой", selection: Binding(
                get: { CalendarMode(rawValue: calendarModeRaw) ?? .none },
                set: { mode in Task { await setCalendarMode(mode) } }
            )) {
                ForEach(CalendarMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if calendarDenied {
                Button("Разрешить доступ в Настройках iPhone") { openSettings() }
            }
        } header: {
            Text("Календарь")
        } footer: {
            Text("Offload сам добавит дела с датой в Календарь или в «Напоминания» и обновит их, если ты что-то поменяешь.")
        }
    }

    private func setCalendarMode(_ mode: CalendarMode) async {
        calendarDenied = false
        if mode != .none && !CalendarSync.hasAccess(for: mode) {
            let granted = await CalendarSync.shared.requestAccess(for: mode)
            guard granted else {
                calendarDenied = true
                return
            }
        }
        calendarModeRaw = mode.rawValue
        settingsChanged()
    }

    // MARK: - Нейросеть

    @ViewBuilder
    private var aiSection: some View {
        Section {
            Picker("Нейросеть", selection: $provider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            SecureField(provider.keyPlaceholder, text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button("Сохранить ключ") {
                provider.saveKey(trimmedKey)
                key = ""
                hasSavedKey = true
                justSaved = true
            }
            .disabled(trimmedKey.isEmpty)

            Button {
                showGuide = true
            } label: {
                Label("Как получить ключ", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Нейросеть · \(provider.keyName.lowercased())")
        } footer: {
            if justSaved {
                Text("Ключ на месте — можно выгружать мысли.")
                    .foregroundStyle(Theme.accent)
            } else if hasSavedKey {
                Text("\(provider.tagline). Ключ уже сохранён — вставь новый, если хочешь заменить.")
            } else {
                Text("\(provider.tagline). Ключ хранится только в защищённом хранилище этого iPhone.")
            }
        }

        if hasSavedKey {
            Section {
                Button("Удалить ключ \(provider.title)", role: .destructive) {
                    provider.deleteKey()
                    hasSavedKey = false
                    justSaved = false
                }
            }
        }
    }

    // MARK: - Помощники

    private func settingsChanged() {
        NotificationCenter.default.post(name: .offloadSettingsChanged, object: nil)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

#Preview {
    SettingsView()
}
