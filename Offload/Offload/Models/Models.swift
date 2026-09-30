import Foundation
import SwiftData

/// Четыре «полочки», по которым Claude раскладывает мысли.
enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case urgent
    case dated
    case ideas
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent: "Сегодня"
        case .dated: "По датам"
        case .ideas: "Идеи"
        case .home: "Быт"
        }
    }

    var subtitle: String {
        switch self {
        case .urgent: "Срочное и то, что лучше сделать сегодня"
        case .dated: "Всё, у чего есть день или срок"
        case .ideas: "Мысли, планы и то, что стоит обдумать"
        case .home: "Покупки, дом и бытовые дела"
        }
    }

    var symbol: String {
        switch self {
        case .urgent: "sun.max"
        case .dated: "calendar"
        case .ideas: "lightbulb"
        case .home: "basket"
        }
    }

    var emptyText: String {
        switch self {
        case .urgent: "На сегодня ничего не горит. Можно выдохнуть."
        case .dated: "Пока никаких дат. Календарь свободен."
        case .ideas: "Идеи появятся здесь, как только ты ими поделишься."
        case .home: "Список покупок пуст — холодильник доволен."
        }
    }
}

/// Один «слив мыслей»: исходный текст и то, что из него получилось.
@Model
final class BrainDump {
    var text: String
    var comment: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \OffloadItem.dump)
    var items: [OffloadItem] = []

    init(text: String, comment: String = "", createdAt: Date = .now) {
        self.text = text
        self.comment = comment
        self.createdAt = createdAt
    }
}

/// Один пункт в списках: дело, идея или покупка.
@Model
final class OffloadItem {
    var title: String
    var categoryRaw: String
    var dueDate: Date?
    var isDone: Bool
    var createdAt: Date
    var dump: BrainDump?

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .ideas }
        set { categoryRaw = newValue.rawValue }
    }

    init(title: String, category: ItemCategory, dueDate: Date? = nil, isDone: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.dueDate = dueDate
        self.isDone = isDone
        self.createdAt = createdAt
    }
}
