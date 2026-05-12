import AppKit
import SwiftUI

@MainActor
private final class AgentController: NSObject {
    private let statusController = StatusBarController()
    private let petWindowController = PetOverlayWindowController()
    private let macNotificationBridge = MacNotificationBridge()
    private let dingTalkStatusBridge = DingTalkStatusBridge()
    private let activityNotificationPresenter = ActivityNotificationPresenter()
    private var activityTimer: Timer?

    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        configureIcon()
        appendAgentLog("agent starting")

        petWindowController.onVisibilityChanged = { [statusController] isVisible in
            statusController.updatePetVisibility(isVisible: isVisible)
        }
        statusController.configure(
            onOpenApp: { AgentActions.openMainApp() },
            onTogglePet: { [petWindowController] in petWindowController.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        petWindowController.show()
        appendAgentLog("status item and sprite configured")
        activityNotificationPresenter.start()
        startActivityHeartbeat()
        startExperimentalBridgesIfEnabled()
        NotificationCenter.default.addObserver(
            forName: AgentActions.activityChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.statusController.refreshActivity()
            }
        }
        app.run()
    }

    private func startExperimentalBridgesIfEnabled() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "RightClickKitAgent.experimentalMacNotificationBridgeEnabled") {
            macNotificationBridge.start()
        }
        if defaults.bool(forKey: "RightClickKitAgent.experimentalDingTalkStatusBridgeEnabled") {
            dingTalkStatusBridge.start()
        }
    }

    private func startActivityHeartbeat() {
        activityTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.statusController.refreshActivity()
                self?.activityNotificationPresenter.refresh()
            }
        }
        activityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func configureIcon() {
        for url in AgentPaths.appIconCandidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = image
                return
            }
        }
    }

    private func appendAgentLog(_ message: String) {
        let url = AgentPaths.logDirectory.appendingPathComponent("agent.log")
        try? FileManager.default.createDirectory(at: AgentPaths.logDirectory, withIntermediateDirectories: true)
        let line = "[\(Date())] \(message)\n"
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
}

@main
enum RightClickKitAgentApplication {
    @MainActor
    private static var controller: AgentController?

    static func main() {
        let controller = AgentController()
        self.controller = controller
        controller.start()
    }
}
