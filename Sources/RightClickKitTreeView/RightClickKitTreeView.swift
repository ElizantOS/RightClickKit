import AppKit
import SwiftUI

@MainActor
private final class TreeViewerController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        configureIcon()

        let request = TreeViewerRequest.parse(arguments: Array(CommandLine.arguments.dropFirst()))
        let rootView = TreeViewerRootView(request: request)
            .frame(minWidth: 1000, minHeight: 680)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Directory Tree"
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
enum RightClickKitTreeViewerApplication {
    @MainActor
    private static var controller: TreeViewerController?

    static func main() {
        let controller = TreeViewerController()
        self.controller = controller
        controller.start()
    }
}
