import Foundation

enum AlertQuietHours {
    static func isActive(
        now: Date = .now,
        calendar: Calendar = .current,
        enabled: Bool,
        startHour: Int,
        endHour: Int
    ) -> Bool {
        guard enabled else { return false }
        let hour = calendar.component(.hour, from: now)
        let start = max(0, min(23, startHour))
        let end = max(0, min(23, endHour))
        if start == end { return false }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}
