import SwiftUI
import WidgetKit

struct SysPulseWidgetEntry: TimelineEntry {
    let date: Date
    let envelope: WidgetSnapshotEnvelope

    var primary: WidgetServerSnapshot {
        envelope.servers.first ?? .placeholder
    }
}

struct SysPulseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SysPulseWidgetEntry {
        SysPulseWidgetEntry(date: .now, envelope: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SysPulseWidgetEntry) -> Void) {
        completion(SysPulseWidgetEntry(date: .now, envelope: WidgetSnapshotStore().load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SysPulseWidgetEntry>) -> Void) {
        let entry = SysPulseWidgetEntry(date: .now, envelope: WidgetSnapshotStore().load() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct SysPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SysPulseWidgetEntry

    var body: some View {
        Group {
            if isLocked {
                locked
            } else {
                switch family {
                case .systemSmall:
                    small
                case .systemMedium:
                    medium
                default:
                    large
                }
            }
        }
        .widgetURL(deepLinkURL)
    }

    private var isLocked: Bool {
        entry.primary.status == "Pro"
    }

    private var deepLinkURL: URL? {
        isLocked
            ? URL(string: "syspulse://paywall")
            : URL(string: "syspulse://server/\(entry.primary.id)")
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.bold))
                .foregroundStyle(.cyan)
            Text("Unlock Pro")
                .font(.headline)
                .lineLimit(1)
            Text("Widgets are included with SysPulse Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .sysPulseWidgetBackground()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                Spacer()
                Circle().fill(statusColor(entry.primary.status)).frame(width: 8, height: 8)
            }
            Text(entry.primary.name)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            Text("Health \(entry.primary.health)")
                .font(.title3.weight(.bold))
        }
        .sysPulseWidgetBackground()
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.primary.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(LocalizedStringKey(entry.primary.status))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(entry.primary.status))
            }
            metricRow("CPU", entry.primary.cpu, .cyan)
            metricRow("RAM", entry.primary.ram, .green)
            metricRow("Disk", entry.primary.disk, entry.primary.disk > 80 ? .orange : .blue)
        }
        .sysPulseWidgetBackground()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SysPulse")
                .font(.title3.weight(.bold))
            ForEach(Array(entry.envelope.servers.prefix(5))) { server in
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(statusColor(server.status))
                    Text(server.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(server.health)")
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .sysPulseWidgetBackground()
    }

    private func metricRow(_ title: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(value / 100, 1))
                    }
            }
            .frame(height: 6)
            Text("\(Int(value))%")
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "online": .green
        case "warning": .yellow
        case "offline": .red
        default: .secondary
        }
    }
}

struct SysPulseWidget: Widget {
    let kind = "SysPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SysPulseWidgetProvider()) { entry in
            SysPulseWidgetView(entry: entry)
        }
        .configurationDisplayName("SysPulse Server")
        .description("Preview server health, CPU, RAM and disk.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension View {
    func sysPulseWidgetBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.11),
                    Color(red: 0.02, green: 0.11, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

@main
struct SysPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        SysPulseWidget()
    }
}
