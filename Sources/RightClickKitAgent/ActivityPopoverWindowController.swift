import AppKit
import RightClickKitCore
import SwiftUI

@MainActor
final class ActivityPopoverWindowController {
    private var window: NSPanel?
    private var anchorFrame: NSRect?

    func show(anchorFrame: NSRect) {
        self.anchorFrame = anchorFrame
        let items = visibleItems()
        let size = NSSize(width: 274, height: ActivityPopoverView.height(itemCount: items.count))
        let frame = popoverFrame(size: size, anchorFrame: anchorFrame)
        let rootView = makeRootView(items: items)

        if let window {
            window.setFrame(frame, display: true, animate: false)
            window.contentView = ActivityPopoverHostingView(rootView: rootView)
            window.orderFrontRegardless()
            return
        }

        let window = ActivityPopoverPanel(
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
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.contentView = ActivityPopoverHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
    }

    func reposition(anchorFrame: NSRect) {
        self.anchorFrame = anchorFrame
        guard let window, window.isVisible else { return }
        let size = NSSize(width: window.frame.width, height: window.frame.height)
        window.setFrame(popoverFrame(size: size, anchorFrame: anchorFrame), display: true, animate: false)
    }

    private func refresh() {
        guard let window, let anchorFrame else { return }
        let items = visibleItems()
        if items.isEmpty {
            hide()
            return
        }

        let size = NSSize(width: 274, height: ActivityPopoverView.height(itemCount: items.count))
        window.setFrame(popoverFrame(size: size, anchorFrame: anchorFrame), display: true, animate: false)
        window.contentView = ActivityPopoverHostingView(rootView: makeRootView(items: items))
    }

    private func makeRootView(items: [ActivityItem]) -> ActivityPopoverView {
        ActivityPopoverView(
            items: items,
            onClose: { [weak self] in
                self?.hide()
            },
            onMarkItemRead: { [weak self] id in
                AgentActions.markActivityRead(id: id)
                self?.refresh()
            },
            onClear: { [weak self] in
                AgentActions.clearActivity()
                self?.hide()
            },
            onOpenLogs: AgentActions.openLogs
        )
    }

    private func visibleItems() -> [ActivityItem] {
        AgentActions.activityItems().filter { $0.readAt == nil }
    }

    private func popoverFrame(size: NSSize, anchorFrame: NSRect) -> NSRect {
        let visible = NSScreen.screens
            .first { $0.frame.intersects(anchorFrame) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 120, y: 120, width: 1440, height: 900)
        let margin: CGFloat = 10
        let preferred = NSPoint(
            x: anchorFrame.minX - size.width + 10,
            y: anchorFrame.minY - max(0, size.height - anchorFrame.height) * 0.55
        )
        let x = min(max(preferred.x, visible.minX + margin), visible.maxX - size.width - margin)
        let y = min(max(preferred.y, visible.minY + margin), visible.maxY - size.height - margin)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

private final class ActivityPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ActivityPopoverHostingView: NSHostingView<ActivityPopoverView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point), !isHidden, alphaValue > 0 else {
            return nil
        }
        return super.hitTest(point) ?? self
    }

    override func scrollWheel(with event: NSEvent) {
        if let scrollView = firstScrollView(in: self) {
            scrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

private struct ActivityPopoverView: View {
    let items: [ActivityItem]

    let onClose: () -> Void
    let onMarkItemRead: (String) -> Void
    let onClear: () -> Void
    let onOpenLogs: () -> Void

    static func height(itemCount: Int) -> CGFloat {
        let count = max(1, min(4, itemCount))
        return CGFloat(count) * 66 + CGFloat(count - 1) * 7 + 56
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ActivityToolbarView(
                unreadCount: items.filter { $0.readAt == nil }.count,
                onClose: onClose,
                onOpenLogs: onOpenLogs,
                onClear: onClear
            )

            ScrollView(.vertical) {
                LazyVStack(alignment: .trailing, spacing: 7) {
                    if items.isEmpty {
                        ActivityCardView(
                            item: ActivityItem(
                                source: "RightClickKit",
                                title: "All caught up",
                                body: "New RightClickKit activity will appear here.",
                                status: .done,
                                readAt: Date()
                            ),
                            onMarkRead: { _ in }
                        )
                    } else {
                        ForEach(items) { item in
                            ActivityCardView(item: item, onMarkRead: onMarkItemRead)
                        }
                    }
                }
                .padding(.bottom, 10)
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.visible)
        }
        .padding(.top, 10)
        .frame(width: 274, height: Self.height(itemCount: items.count), alignment: .trailing)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
    }
}

private struct ActivityToolbarView: View {
    let unreadCount: Int
    let onClose: () -> Void
    let onOpenLogs: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(unreadCount == 0 ? "History" : "\(unreadCount) unread")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onOpenLogs) {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Open logs")
            Button(action: onClear) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Clear history")
            Button(action: onClose) {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .frame(width: 258, height: 28)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
        .padding(.horizontal, 8)
    }
}

private struct ActivityCardView: View {
    let item: ActivityItem
    let onMarkRead: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button {
                onMarkRead(item.id)
            } label: {
                Circle()
                    .strokeBorder(statusColor, lineWidth: item.readAt == nil ? 2 : 1)
                    .background(Circle().fill(item.readAt == nil ? statusColor.opacity(0.18) : Color.clear))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .disabled(item.readAt != nil)
            .help(item.readAt == nil ? "Mark read" : "Read")
            .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 258, alignment: .topLeading)
        .frame(minHeight: 58, alignment: .topLeading)
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    private var statusColor: Color {
        switch item.status {
        case .running:
            Color(red: 0.12, green: 0.48, blue: 0.95)
        case .waiting:
            Color(red: 0.90, green: 0.55, blue: 0.12)
        case .failed:
            Color(red: 0.86, green: 0.18, blue: 0.14)
        case .review, .done:
            Color(red: 0.16, green: 0.63, blue: 0.27)
        }
    }
}
