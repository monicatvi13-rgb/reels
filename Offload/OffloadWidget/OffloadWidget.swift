import WidgetKit
import SwiftUI

/// Виджет Offload: одна кнопка — и сразу разговор с помощником.
@main
struct OffloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        OffloadTalkWidget()
    }
}

struct OffloadTalkWidget: Widget {
    let kind = "OffloadTalkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TalkProvider()) { _ in
            TalkWidgetView()
        }
        .configurationDisplayName("Поговорить с Offload")
        .description("Нажми — и сразу говори: помощник слушает.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TalkEntry: TimelineEntry {
    let date: Date
}

struct TalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkEntry { TalkEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TalkEntry) -> Void) {
        completion(TalkEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkEntry>) -> Void) {
        // Виджет не меняется со временем — обновлять его не нужно.
        completion(Timeline(entries: [TalkEntry(date: .now)], policy: .never))
    }
}

private enum WidgetColors {
    static let cream = Color(red: 0xF6 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
    static let sage = Color(red: 0x6F / 255, green: 0x8F / 255, blue: 0x7A / 255)
    static let ink = Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x26 / 255)
}

struct TalkWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let talkURL = URL(string: "offload://talk")!

    var body: some View {
        content
            .widgetURL(talkURL)
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    WidgetColors.cream
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Поговорить с Offload")

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offload")
                        .font(.headline)
                    Text("Нажми и говори")
                        .font(.caption)
                }
            }

        case .systemMedium:
            HStack(spacing: 16) {
                micCircle(size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Что крутится в голове?")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(WidgetColors.ink)
                    Text("Нажми и говори — разложу по полочкам и напомню.")
                        .font(.caption)
                        .foregroundStyle(WidgetColors.ink.opacity(0.6))
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(alignment: .leading, spacing: 10) {
                micCircle(size: 56)
                Spacer(minLength: 0)
                Text("Нажми и говори")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetColors.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func micCircle(size: CGFloat) -> some View {
        Circle()
            .fill(WidgetColors.sage)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
