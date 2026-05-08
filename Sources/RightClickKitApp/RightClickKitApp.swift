import AppKit
import SwiftUI

@MainActor
final class RightClickKitController {
    private var window: NSWindow?

    func start() {
        fputs("RightClickKit window launched\n", stderr)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let contentView = ContentView()
            .frame(minWidth: 920, minHeight: 620)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "RightClickKit"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

@main
enum RightClickKitApplication {
    static func main() {
        RightClickKitController().start()
    }
}
