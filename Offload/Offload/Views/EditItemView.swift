import SwiftUI
import SwiftData

/// Лист для правки пункта или добавления нового вручную.
struct EditItemView: View {
    let item: OffloadItem?
    let defaultCategory: ItemCategory

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: ItemCategory = .urgent
    @State private var hasDate = false
    @State private var date = Date.now
    @State private var isDone = false
    @State private var confirmDelete = false

    private var isNew: Bool { item == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что нужно не забыть?", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Полочка") {
                    Picker("Полочка", selection: $category) {
                        ForEach(ItemCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Toggle("Есть дата", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Когда", selection: $date, displayedComponents: .date)
                    }
                    if !isNew {
                        Toggle("Уже сделано", isOn: $isDone)
                    }
                }

                if !isNew {
                    Section {
                        Button("Удалить", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? "Новый пункт" : "Поправить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить этот пункт?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let item { context.delete(item) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let item else {
            category = defaultCategory
            return
        }
        title = item.title
        category = item.category
        hasDate = item.dueDate != nil
        date = item.dueDate ?? .now
        isDone = item.isDone
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = hasDate ? date : nil

        if let item {
            item.title = cleanTitle
            item.category = category
            item.dueDate = dueDate
            item.isDone = isDone
        } else {
            context.insert(OffloadItem(title: cleanTitle, category: category, dueDate: dueDate))
        }
        dismiss()
    }
}
