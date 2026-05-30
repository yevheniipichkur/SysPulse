import Foundation
import SwiftUI

enum StatusToastStyle: Equatable {
    case info
    case success
    case error
}

struct StatusToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let style: StatusToastStyle
}

extension AppState {
    func postStatus(_ message: String, style: StatusToastStyle = .info) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statusToast = StatusToast(message: trimmed, style: style)
        statusToastDismissTask?.cancel()
        statusToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            if statusToast?.message == trimmed {
                statusToast = nil
            }
        }
    }

    func setRemoteCommandOutput(_ output: String) {
        remoteCommandOutput = output
    }

    func clearRemoteCommandOutput() {
        remoteCommandOutput = ""
    }

    func scheduleWidgetSnapshotPublish() {
        widgetPublishTask?.cancel()
        widgetPublishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            publishWidgetSnapshots()
        }
    }
}
