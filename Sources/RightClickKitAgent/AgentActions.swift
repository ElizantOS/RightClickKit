import AppKit
import Foundation
import RightClickKitCore

struct AgentMenuAction: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
}

enum AgentActions {
    static let activityChangedNotification = Notification.Name("RightClickKitAgent.activityChanged")

    static func openMainApp() {
        let appURL = AgentPaths.mainAppURL
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
        }
    }

    static func openNativeTool(named executableName: String) {
        let helperURL = AgentPaths.helperAppURL(named: executableName)
        if FileManager.default.fileExists(atPath: helperURL.path) {
            NSWorkspace.shared.open(helperURL)
            return
        }

        let binaryURL = AgentPaths.binDirectory.appendingPathComponent(executableName)
        if FileManager.default.isExecutableFile(atPath: binaryURL.path) {
            let process = Process()
            process.executableURL = binaryURL
            try? process.run()
        }
    }

    static func openLogs() {
        NSWorkspace.shared.open(AgentPaths.logDirectory)
    }

    static func activitySummary() -> ActivitySummary {
        (try? ActivityStore().summary()) ?? .empty
    }

    static func activityItems() -> [ActivityItem] {
        (try? ActivityStore().list()) ?? []
    }

    static func markActivityRead() {
        try? ActivityStore().markAllRead()
        notifyActivityChanged()
    }

    static func markActivityRead(id: String) {
        try? ActivityStore().markRead(id: id)
        notifyActivityChanged()
    }

    static func clearActivity() {
        try? ActivityStore().clear()
        notifyActivityChanged()
    }

    static func notifyActivityChanged() {
        NotificationCenter.default.post(name: activityChangedNotification, object: nil)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.elizantos.RightClickKit.Agent"
        let specificURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
        let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let specificURL {
            NSWorkspace.shared.open(specificURL)
        } else if let fallbackURL {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    static func revealAgentForFullDiskAccess() {
        NSWorkspace.shared.activateFileViewerSelecting([AgentPaths.agentAppURL])
    }

    static func loadMenuActions() -> [AgentMenuAction] {
        do {
            let config = try currentConfig()
            let services = try ServiceStore(servicesDirectory: config.servicesURL).loadServices()
            return services
                .filter(\.enabled)
                .map { service in
                    AgentMenuAction(
                        id: service.id,
                        title: service.title,
                        systemImage: service.action?.type.systemImage ?? "gearshape"
                    )
                }
        } catch {
            return []
        }
    }

    static func runConfiguredAction(id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let config = try currentConfig()
                let status = try ServiceRunner(config: config).run(serviceID: id, arguments: [])
                if status != 0 {
                    DispatchQueue.main.async {
                        openLogs()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    openLogs()
                }
            }
        }
    }

    private static func currentConfig() throws -> RightClickKitConfig {
        let paths = RCKPaths()
        if FileManager.default.fileExists(atPath: paths.configURL.path) {
            return try ConfigStore(paths: paths).load()
        }

        if let repositoryRoot = bundledRepositoryRoot() {
            return RightClickKitConfig(
                repositoryRoot: repositoryRoot.path,
                rckPath: AgentPaths.binDirectory.appendingPathComponent("rck").path
            )
        }

        return RightClickKitConfig(
            repositoryRoot: FileManager.default.currentDirectoryPath,
            rckPath: AgentPaths.binDirectory.appendingPathComponent("rck").path
        )
    }

    private static func bundledRepositoryRoot() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("repository-root.txt"),
            AgentPaths.mainAppURL.appendingPathComponent("Contents/Resources/repository-root.txt")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let text = try? String(contentsOf: candidate, encoding: .utf8) else {
                continue
            }
            let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }

            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("services").path) {
                return url
            }
        }
        return nil
    }
}

enum AgentPaths {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rightclickkit", isDirectory: true)
    }

    static var binDirectory: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    static var mainAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/RightClickKit.app", isDirectory: true)
    }

    static var agentAppURL: URL {
        helperAppURL(named: "RightClickKitAgent")
    }

    static func helperAppURL(named executableName: String) -> URL {
        mainAppURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("\(executableName).app", isDirectory: true)
    }

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RightClickKit", isDirectory: true)
    }

    static var appIconCandidates: [URL] {
        [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            mainAppURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        ].compactMap { $0 }
    }
}
