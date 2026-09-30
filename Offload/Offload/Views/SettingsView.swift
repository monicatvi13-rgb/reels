import SwiftUI

/// Настройки: выбор нейросети и её ключ.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var provider: AIProvider = .current
    @State private var key = ""
    @State private var hasSavedKey = AIProvider.current.savedKey != nil
    @State private var justSaved = false
    @State private var showGuide = false

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Нейросеть", selection: $provider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(provider.tagline)
                }

                Section {
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
                } header: {
                    Text(provider.keyName)
                } footer: {
                    if justSaved {
                        Text("Ключ на месте — можно выгружать мысли.")
                            .foregroundStyle(Theme.accent)
                    } else if hasSavedKey {
                        Text("Ключ уже сохранён. Вставь новый, если хочешь заменить.")
                    } else {
                        Text("Ключ хранится только в защищённом хранилище этого iPhone.")
                    }
                }

                Section {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Как получить ключ", systemImage: "questionmark.circle")
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
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Нейросеть")
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
}

#Preview {
    SettingsView()
}
