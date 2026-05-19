import SwiftUI
import WidgetKit

struct SysPulseWidgetEntry: TimelineEntry {
    let date: Date
    let serverName: String
    let status: String
    let cpu: Double
    let ram: Double
    let disk: Double
    let health: Int
}

struct SysPulseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SysPulseWidgetEntry {
        SysPulseWidgetEntry(date: .now, serverName: "Raspberry Pi", status: "Online", cpu: 27, ram: 54, disk: 68, health: 91)
    }

    func getSnapshot(in context: Context, completion: @escaping (SysPulseWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SysPulseWidgetEntry>) -> Void) {
        let entry = SysPulseWidgetEntry(date: .now, serverName: "Demo Server", status: "Online", cpu: 42, ram: 63, disk: 57, health: 84)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct SysPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SysPulseWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            large
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            Text(entry.serverName)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            Text("Health \(entry.health)")
                .font(.title3.weight(.bold))
        }
        .sysPulseWidgetBackground()
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.serverName)
                    .font(.headline)
                Spacer()
                Text(entry.status)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }
            metricRow("CPU", entry.cpu, .cyan)
            metricRow("RAM", entry.ram, .green)
            metricRow("Disk", entry.disk, entry.disk > 80 ? .orange : .blue)
        }
        .sysPulseWidgetBackground()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SysPulse")
                .font(.title3.weight(.bold))
            ForEach(["Raspberry Pi Home", "VPS Production", "Docker Lab"], id: \.self) { name in
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.cyan)
                    Text(name)
                        .lineLimit(1)
                    Spacer()
                    Text(name == "VPS Production" ? "66" : "91")
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .sysPulseWidgetBackground()
    }

    private func metricRow(_ title: String, _ value: Double, _ color: Color) -> some View {
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
