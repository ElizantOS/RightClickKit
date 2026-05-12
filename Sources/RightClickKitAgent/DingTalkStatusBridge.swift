import ApplicationServices
import AppKit
import Foundation
import RightClickKitCore

@MainActor
final class DingTalkStatusBridge {
    private var timer: Timer?
    private var lastUnreadText = ""
    private var didPostAccessibilityWarning = false

    func start() {
        poll()
        let timer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard AXIsProcessTrusted() else {
            lastUnreadText = ""
            postAccessibilityWarning()
            return
        }
        didPostAccessibilityWarning = false

        guard let unreadText = DingTalkStatusReader.unreadBadgeText() else {
            if !lastUnreadText.isEmpty {
                lastUnreadText = ""
            }
            return
        }
        guard unreadText != lastUnreadText else { return }
        lastUnreadText = unreadText
        postUnreadBadge(unreadText)
    }

    private func postAccessibilityWarning() {
        guard !didPostAccessibilityWarning else { return }
        didPostAccessibilityWarning = true
        _ = try? ActivityStore().append(
            id: "dingtalk-status:accessibility-required",
            source: "RightClickKit",
            title: "Enable DingTalk unread bridge",
            body: "Grant Accessibility access to RightClickKitAgent so it can read DingTalk's menu bar unread badge.",
            status: .waiting,
            level: .warning,
            actionID: "dingtalk-status-bridge"
        )
        AgentActions.notifyActivityChanged()
    }

    private func postUnreadBadge(_ unreadText: String) {
        _ = try? ActivityStore().append(
            id: "dingtalk-status:unread-badge",
            source: "DingTalk",
            title: "DingTalk unread \(unreadText)",
            body: "Detected from the DingTalk menu bar badge. Message content still depends on macOS notifications.",
            status: .waiting,
            level: .warning,
            actionID: "dingtalk-status-bridge"
        )
        AgentActions.notifyActivityChanged()
    }
}

private enum DingTalkStatusReader {
    static func unreadBadgeText() -> String? {
        for app in NSWorkspace.shared.runningApplications where isDingTalk(app) {
            guard let pid = app.processIdentifier as pid_t?,
                  let text = unreadBadgeText(pid: pid)
            else {
                continue
            }
            return text
        }
        return nil
    }

    private static func isDingTalk(_ app: NSRunningApplication) -> Bool {
        let bundleIdentifier = app.bundleIdentifier?.lowercased() ?? ""
        let localizedName = app.localizedName?.lowercased() ?? ""
        return bundleIdentifier.contains("dingtalk")
            || bundleIdentifier.contains("rimet")
            || localizedName.contains("dingtalk")
            || localizedName.contains("钉钉")
    }

    private static func unreadBadgeText(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        for attribute in ["AXExtrasMenuBar", kAXMenuBarAttribute] {
            guard let menuBarValue = copyAttribute(appElement, attribute) else {
                continue
            }
            guard CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
                continue
            }
            let menuBar = menuBarValue as! AXUIElement
            if let text = firstUnreadBadge(in: menuBar) {
                return text
            }
        }
        return nil
    }

    private static func firstUnreadBadge(in element: AXUIElement) -> String? {
        for text in accessibilityTexts(from: element) {
            if isUnreadBadgeText(text) {
                return text
            }
        }

        guard let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let text = firstUnreadBadge(in: child) {
                return text
            }
        }
        return nil
    }

    private static func accessibilityTexts(from element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { copyAttribute(element, $0) as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isUnreadBadgeText(_ text: String) -> Bool {
        text.range(of: #"^[0-9]{1,3}\+?$"#, options: .regularExpression) != nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }
}
