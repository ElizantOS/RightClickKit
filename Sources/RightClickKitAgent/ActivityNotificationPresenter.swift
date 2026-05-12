import Foundation
import RightClickKitCore
import UserNotifications

@MainActor
final class ActivityNotificationPresenter {
    private var deliveredIDs = Set<String>()
    private var didRequestAuthorization = false

    func start() {
        requestAuthorizationIfNeeded()
        refresh()
    }

    func refresh() {
        requestAuthorizationIfNeeded()
        guard let items = try? ActivityStore().list() else { return }
        let unread = items.filter { $0.readAt == nil && !deliveredIDs.contains($0.id) }
        for item in unread {
            deliver(item)
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            appendNotificationLog("settings bundle=\(bundleID) authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue)")
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            appendNotificationLog("authorization bundle=\(bundleID) granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    private func deliver(_ item: ActivityItem) {
        deliveredIDs.insert(item.id)
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.subtitle = item.source
        content.body = item.body.isEmpty ? item.status.rawValue.capitalized : item.body
        content.sound = notificationSound(for: item)
        content.userInfo = ["activityID": item.id]

        let request = UNNotificationRequest(
            identifier: "rightclickkit.activity.\(item.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appendNotificationLog("delivery failed id=\(item.id): \(error.localizedDescription)")
            } else {
                appendNotificationLog("delivered id=\(item.id) title=\(item.title)")
            }
        }
    }

    private func notificationSound(for item: ActivityItem) -> UNNotificationSound? {
        switch item.level {
        case .danger, .warning:
            return .default
        case .info, .success:
            return nil
        }
    }
}

private nonisolated func appendNotificationLog(_ message: String) {
    let url = AgentPaths.logDirectory.appendingPathComponent("agent.log")
    try? FileManager.default.createDirectory(at: AgentPaths.logDirectory, withIntermediateDirectories: true)
    let line = "[\(Date())] activity notification: \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    } catch {
        return
    }
}
