import Foundation

enum ServerCompareSortMode: String, CaseIterable, Identifiable {
    case health
    case cpu
    case ram
    case disk
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .health: "Health"
        case .cpu: "CPU"
        case .ram: "RAM"
        case .disk: "Disk"
        case .name: "Name"
        }
    }
}

enum ServerCompareSorting {
    static func sorted(
        _ pairs: [(ServerProfile, ServerMetrics)],
        by mode: ServerCompareSortMode
    ) -> [(ServerProfile, ServerMetrics)] {
        switch mode {
        case .health:
            return pairs.sorted { $0.1.healthScore < $1.1.healthScore }
        case .cpu:
            return pairs.sorted { $0.1.cpuUsage > $1.1.cpuUsage }
        case .ram:
            return pairs.sorted { $0.1.ramUsage > $1.1.ramUsage }
        case .disk:
            return pairs.sorted { $0.1.diskUsage > $1.1.diskUsage }
        case .name:
            return pairs.sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
        }
    }
}
