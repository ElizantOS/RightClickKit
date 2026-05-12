import AppKit
import RightClickKitCore

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var activityMenuItem: ClosureMenuItem?
    private var petVisibilityItem: ClosureMenuItem?
    private var visibilityProbeChecksRemaining = 0
    private var isPetVisible = true

    func configure(
        onOpenApp: @escaping () -> Void,
        onTogglePet: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = statusImage(named: "bolt.circle", description: "RightClickKit")
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.wantsLayer = false
            button.toolTip = "RightClickKit"
            button.setAccessibilityTitle("RightClickKit")
        }

        menu.removeAllItems()
        let activityItem = item("No Activity", systemImage: "bell", action: AgentActions.markActivityRead)
        activityItem.isEnabled = false
        activityMenuItem = activityItem
        menu.addItem(activityItem)
        menu.addItem(item("Mark Activity Read", systemImage: "checkmark.circle", action: {
            AgentActions.markActivityRead()
            self.refreshActivity()
        }))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Open RightClickKit", systemImage: "app", action: onOpenApp))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Full Disk Access...", systemImage: "lock.shield", action: AgentActions.openFullDiskAccessSettings))
        menu.addItem(item("Accessibility Access...", systemImage: "figure.stand", action: AgentActions.openAccessibilitySettings))
        menu.addItem(item("Notification Settings...", systemImage: "bell.badge", action: AgentActions.openNotificationSettings))
        menu.addItem(item("Reveal Agent for Access", systemImage: "app.badge", action: AgentActions.revealAgentForFullDiskAccess))
        menu.addItem(NSMenuItem.separator())
        let petItem = item("Hide Sprite", systemImage: "flame", action: {
            onTogglePet()
        })
        petVisibilityItem = petItem
        menu.addItem(petItem)
        menu.addItem(item("Open Logs", systemImage: "doc.text.magnifyingglass", action: AgentActions.openLogs))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit RightClickKit Agent", systemImage: "xmark.circle", action: onQuit))
        statusItem.menu = menu
        appendStatusLog("status item configured: length=\(statusItem.length), visible=\(statusItem.isVisible)")
        refreshActivity()
        startVisibilityProbe()
    }

    func updatePetVisibility(isVisible: Bool) {
        isPetVisible = isVisible
        petVisibilityItem?.title = isVisible ? "Hide Sprite" : "Show Sprite"
        petVisibilityItem?.image = NSImage(
            systemSymbolName: isVisible ? "flame" : "flame.slash",
            accessibilityDescription: petVisibilityItem?.title
        )
    }

    func refreshActivity() {
        let summary = AgentActions.activitySummary()
        let title: String
        let symbol: String
        if summary.runningCount > 0 {
            title = "\(summary.runningCount) Running"
            symbol = "arrow.triangle.2.circlepath"
        } else if summary.failedCount > 0 {
            title = "\(summary.failedCount) Failed"
            symbol = "exclamationmark.triangle"
        } else if summary.waitingCount > 0 {
            title = "\(summary.waitingCount) Waiting"
            symbol = "hourglass"
        } else if summary.reviewCount > 0 {
            title = "\(summary.reviewCount) New Activity"
            symbol = "bell.badge"
        } else {
            title = "No Activity"
            symbol = "bell"
        }

        activityMenuItem?.title = title
        activityMenuItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        activityMenuItem?.isEnabled = summary.badgeCount > 0
        statusItem.button?.image = statusImage(named: statusSymbol(for: summary), description: title)
        statusItem.button?.toolTip = "RightClickKit - \(title)"
    }

    private func statusSymbol(for summary: ActivitySummary) -> String {
        if summary.runningCount > 0 {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        if summary.failedCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if summary.waitingCount > 0 {
            return "bell.badge.fill"
        }
        if summary.reviewCount > 0 {
            return "bell.badge"
        }
        return "bolt.circle.fill"
    }

    private func statusImage(named name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private func startVisibilityProbe() {
        visibilityProbeChecksRemaining = 8
        scheduleVisibilityProbeTick()
    }

    private func scheduleVisibilityProbeTick() {
        guard visibilityProbeChecksRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor in
                self?.runVisibilityProbeTick()
            }
        }
    }

    private func runVisibilityProbeTick() {
        guard visibilityProbeChecksRemaining > 0 else { return }
        logVisibilityStateIfReady()
        visibilityProbeChecksRemaining -= 1
        scheduleVisibilityProbeTick()
    }

    private func logVisibilityStateIfReady() {
        guard let frame = statusItem.button?.window?.frame, frame.width > 0 else { return }
        let state = visibilityState(for: frame)
        appendStatusLog("status item \(state): frame=\(frame)")
        visibilityProbeChecksRemaining = 1
    }

    private func visibilityState(for frame: NSRect) -> String {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            return "visible-unknown-screen"
        }
        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea
        {
            let visibleInRightStatusArea = frame.intersection(rightArea).width
            if visibleInRightStatusArea > 1 {
                return "visible-in-right-status-area"
            }
            let hiddenByNotchBand = NSRect(
                x: leftArea.maxX,
                y: min(leftArea.minY, rightArea.minY) - 4,
                width: max(0, rightArea.minX - leftArea.maxX),
                height: max(leftArea.height, rightArea.height) + 8
            )
            if frame.intersects(hiddenByNotchBand) {
                return "obscured-by-notch-or-crowded-menu-bar"
            }
            if frame.maxX <= leftArea.maxX {
                return "obscured-by-active-app-menu"
            }
        }
        return "visible"
    }

    private func item(_ title: String, systemImage: String, action: @escaping () -> Void) -> ClosureMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }

    private func appendStatusLog(_ message: String) {
        let url = AgentPaths.logDirectory.appendingPathComponent("agent.log")
        try? FileManager.default.createDirectory(at: AgentPaths.logDirectory, withIntermediateDirectories: true)
        let line = "[\(Date())] status bar: \(message)\n"
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

private final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, action closure: @escaping () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(runClosure), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runClosure() {
        closure()
    }
}
