import AppKit
import SwiftUI

@MainActor
final class PetOverlayWindowController {
    private var window: NSPanel?
    private let activityPopoverController = ActivityPopoverWindowController()
    private var dragMouseOffset: CGSize?
    var onVisibilityChanged: ((Bool) -> Void)?

    func show() {
        if let window {
            window.orderFrontRegardless()
            onVisibilityChanged?(true)
            return
        }

        let size = PetOverlayView.windowSize(for: PetOverlayPreferences.scale)
        let frame = defaultFrame(size: size)
        let window = DraggablePetPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.contentView = NSHostingView(rootView: PetOverlayView(
            onScaleChanged: { [weak self] scale in
                self?.resize(to: scale)
            },
            onHide: { [weak self] in
                self?.hide()
            },
            onShowActivity: { [weak self] in
                self?.showActivity()
            },
            onDragBegan: { [weak self] in
                self?.beginDrag()
            },
            onDragChanged: { [weak self] in
                self?.moveDrag()
            },
            onDragEnded: { [weak self] in
                self?.endDrag()
            }
        ))
        window.orderFrontRegardless()
        self.window = window
        onVisibilityChanged?(true)
    }

    func toggle() {
        if let window, window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func hide() {
        window?.orderOut(nil)
        activityPopoverController.hide()
        onVisibilityChanged?(false)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private func resize(to scale: PetOverlayScale) {
        guard let window else { return }

        let oldFrame = window.frame
        let size = PetOverlayView.windowSize(for: scale)
        let frame = NSRect(
            x: oldFrame.maxX - size.width,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true, animate: false)
        activityPopoverController.reposition(anchorFrame: frame)
    }

    private func showActivity() {
        guard let window else { return }
        activityPopoverController.show(anchorFrame: window.frame)
    }

    private func beginDrag() {
        guard let window else { return }

        let mouse = NSEvent.mouseLocation
        dragMouseOffset = CGSize(
            width: mouse.x - window.frame.origin.x,
            height: mouse.y - window.frame.origin.y
        )
    }

    private func moveDrag() {
        guard let window, let dragMouseOffset else { return }

        let mouse = NSEvent.mouseLocation
        let target = NSRect(
            x: mouse.x - dragMouseOffset.width,
            y: mouse.y - dragMouseOffset.height,
            width: window.frame.width,
            height: window.frame.height
        )
        let frame = clampedFrame(target)
        window.setFrame(frame, display: true, animate: false)
        activityPopoverController.reposition(anchorFrame: frame)
    }

    private func endDrag() {
        moveDrag()
        dragMouseOffset = nil
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        let visible = screenVisibleFrame(for: frame)
        let margin: CGFloat = 8
        return NSRect(
            x: min(max(frame.origin.x, visible.minX + margin), visible.maxX - frame.width - margin),
            y: min(max(frame.origin.y, visible.minY + margin), visible.maxY - frame.height - margin),
            width: frame.width,
            height: frame.height
        )
    }

    private func screenVisibleFrame(for frame: NSRect) -> NSRect {
        NSScreen.screens
            .first { $0.frame.intersects(frame) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 1440, height: 900)
    }

    private func defaultFrame(size: NSSize) -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 1440, height: 900)
        return NSRect(
            x: visible.maxX - size.width - 34,
            y: visible.maxY - size.height - 34,
            width: size.width,
            height: size.height
        )
    }
}

private final class DraggablePetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
