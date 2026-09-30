import SwiftUI

/// Настройки: здесь хранится ключ Claude API.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var hasSavedKey = KeychainStore.read() != nil
    @State private var justSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    Button("Сохранить ключ") {
                        KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        key = ""
                        hasSavedKey = true
                        justSaved = true
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Ключ Claude API")
                } footer: {
                    if justSaved {
                        Text("Ключ на месте — можно выгружать мысли.")
                            .foregroundStyle(Theme.accent)
                    } else if hasSavedKey {
                        Text("Ключ уже сохранён. Вставь новый, если хочешь заменить.")
                    } else {
                        Text("Ключ хранится только в защищённом хранилище этого iPhone и никуда больше не отправляется, кроме Claude.")
                    }
                }

                Section {
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Где взять ключ", systemImage: "arrow.up.right.square")
                    }
                }

                if hasSavedKey {
                    Section {
                        Button("Удалить ключ", role: .destructive) {
                            KeychainStore.delete()
                            hasSavedKey = false
                            justSaved = false
                        }
                    }
                }
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
        }
    }
}

#Preview {
    SettingsView()
}
