import SwiftUI
import SwiftData

/// Экран «Мои списки»: всё, что разложил Claude, по четырём полочкам.
struct ListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OffloadItem.createdAt, order: .reverse) private var allItems: [OffloadItem]

    @State private var category: ItemCategory = .urgent
    @State private var editing: EditTarget?

    private var items: [OffloadItem] {
        let filtered = allItems.filter { $0.category == category }
        guard category == .dated else { return filtered }
        // В «По датам» — ближайшие дела сверху.
        return filtered.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var active: [OffloadItem] { items.filter { !$0.isDone } }
    private var done: [OffloadItem] { items.filter { $0.isDone } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Полочка", selection: $category) {
                        ForEach(ItemCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(category.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Мои списки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EditTarget(item: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Добавить пункт")
                }
                if !done.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Убрать сделанное") {
                            withAnimation {
                                done.forEach {
                                    CalendarSync.shared.remove($0)
                                    context.delete($0)
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(item: $editing) { target in
                EditItemView(item: target.item, defaultCategory: category)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(active) { item in
                    row(item)
                }
                .onDelete { delete(active, at: $0) }
            }

            if !done.isEmpty {
                Section("Сделано") {
                    ForEach(done) { item in
                        row(item)
                    }
                    .onDelete { delete(done, at: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .animation(.default, value: items.map(\.isDone))
    }

    private func row(_ item: OffloadItem) -> some View {
        ItemRow(item: item) {
            editing = EditTarget(item: item)
        }
        .listRowBackground(Theme.card)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: category.symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(category.emptyText)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func delete(_ source: [OffloadItem], at offsets: IndexSet) {
        withAnimation {
            offsets.map { source[$0] }.forEach {
                CalendarSync.shared.remove($0)
                context.delete($0)
            }
        }
    }
}

/// Что открыть в листе редактирования: существующий пункт или новый.
struct EditTarget: Identifiable {
    let id = UUID()
    let item: OffloadItem?
}

/// Одна строка списка: кружок-галочка, текст и дата.
struct ItemRow: View {
    @Bindable var item: OffloadItem
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.snappy) { item.isDone.toggle() }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? Theme.accent : Theme.muted.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: item.isDone)
            .accessibilityLabel(item.isDone ? "Вернуть в работу" : "Отметить сделанным")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .foregroundStyle(item.isDone ? Theme.muted : Theme.ink)
                    .strikethrough(item.isDone, color: Theme.muted)

                if let date = item.dueDate {
                    Label(Self.format(date, hasTime: item.hasTime), systemImage: item.hasTime ? "clock" : "calendar")
                        .font(.caption)
                        .foregroundStyle(Self.isOverdue(date) && !item.isDone ? Theme.recording : Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .padding(.vertical, 6)
    }

    static func format(_ date: Date, hasTime: Bool) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) { day = "Сегодня" }
        else if calendar.isDateInTomorrow(date) { day = "Завтра" }
        else { day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)) }
        return hasTime ? "\(day), \(Briefing.timeString(date))" : day
    }

    static func isOverdue(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: .now)
    }
}

#Preview {
    ListsView()
        .modelContainer(for: [BrainDump.self, OffloadItem.self, ChatEntry.self], inMemory: true)
}
