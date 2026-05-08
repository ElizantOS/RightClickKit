import AppKit
import SwiftUI

@MainActor
private final class StorageViewerController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        configureIcon()

        let request = StorageViewerRequest.parse(arguments: Array(CommandLine.arguments.dropFirst()))
        let rootView = StorageViewerRootView(request: request)
        .frame(minWidth: 960, minHeight: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Storage Analysis"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func configureIcon() {
        let candidates = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Applications/RightClickKit.app/Contents/Resources/AppIcon.icns")
        ].compactMap { $0 }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = image
                return
            }
        }
    }
}

@main
enum RightClickKitStorageViewerApplication {
    @MainActor
    private static var controller: StorageViewerController?

    static func main() {
        let controller = StorageViewerController()
        self.controller = controller
        controller.start()
    }
}
