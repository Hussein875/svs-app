//
//  GutachtenNumberWidget.swift
//  GutachtenNumberWidget
//

import WidgetKit
import SwiftUI

struct GutachtenNumberEntry: TimelineEntry {
    let date: Date
    let snapshot: ScannerWidgetSnapshot.Data
}

struct GutachtenNumberProvider: TimelineProvider {
    func placeholder(in context: Context) -> GutachtenNumberEntry {
        GutachtenNumberEntry(
            date: Date(),
            snapshot: ScannerWidgetSnapshot.Data(
                numberText: "650/26",
                statusText: "Verfügbar",
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GutachtenNumberEntry) -> Void) {
        completion(
            GutachtenNumberEntry(
                date: Date(),
                snapshot: ScannerWidgetSnapshot.load()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GutachtenNumberEntry>) -> Void) {
        let entry = GutachtenNumberEntry(
            date: Date(),
            snapshot: ScannerWidgetSnapshot.load()
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct GutachtenNumberWidget: Widget {
    let kind = ScannerWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GutachtenNumberProvider()) { entry in
            GutachtenNumberWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "svsapp://dashboard"))
                .widgetBackground()
        }
        .configurationDisplayName("Gutachten-Nr.")
        .description("Zeigt die aktuelle Gutachten-Nummer aus SVS Office.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline]
        #else
        return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        #if os(watchOS)
        containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        #else
        containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        #endif
    }
}

struct GutachtenNumberWidgetView: View {
    let snapshot: ScannerWidgetSnapshot.Data

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(snapshot.numberText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

        case .accessoryCorner:
            Text(snapshot.numberText)
                .font(.system(.body, design: .rounded).weight(.bold))
                .widgetCurvesContent()
                .widgetLabel {
                    Text("Gutachten")
                }

        case .accessoryInline:
            Text(snapshot.numberText)
                .fontWeight(.semibold)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Gutachten-Nr.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(snapshot.numberText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .systemMedium:
            HStack(spacing: 16) {
                iconBadge

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gutachten-Nr.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.numberText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(snapshot.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(4)

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    iconBadge
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text(snapshot.numberText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Text(snapshot.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 36, height: 36)
            Image(systemName: "number")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

#if os(iOS)
#Preview(as: .systemSmall) {
    GutachtenNumberWidget()
} timeline: {
    GutachtenNumberEntry(
        date: .now,
        snapshot: ScannerWidgetSnapshot.Data(
            numberText: "650/26",
            statusText: "Verfügbar",
            updatedAt: .now
        )
    )
}
#endif
