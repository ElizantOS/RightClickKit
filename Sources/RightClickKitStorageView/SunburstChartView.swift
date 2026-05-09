import RightClickKitCore
import AppKit
import SwiftUI

struct SunburstChartView: View {
    let root: StorageAnalysisNode
    let selectedNode: StorageAnalysisNode
    var onHover: (StorageAnalysisNode?) -> Void
    var onSelect: (StorageAnalysisNode) -> Void
    var onBack: () -> Void
    @State private var hoveredNodeID: String?

    private var segments: [SunburstSegment] {
        SunburstLayout.segments(for: selectedNode)
    }

    var body: some View {
        ZStack {
            ChartCanvas(segments: segments, highlightedNodeID: hoveredNodeID)

            ChartInteractionLayer(
                segments: segments,
                hoveredNodeID: $hoveredNodeID,
                onHover: onHover,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                hoveredNodeID = nil
                onHover(nil)
                if selectedNode.stableID != root.stableID {
                    onBack()
                }
            } label: {
                VStack(spacing: 5) {
                    Text(StorageFormatter.bytes(selectedNode.bytes))
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(selectedNode.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StoragePalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 128)

                    if selectedNode.stableID != root.stableID {
                        Label("Back", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(StoragePalette.blue)
                    }
                }
                .padding(14)
                .frame(width: 156, height: 156)
                .rckGlassSurface(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .help(selectedNode.stableID == root.stableID ? "Root" : "Back")
        }
        .padding(24)
    }
}

private struct ChartCanvas: View {
    let segments: [SunburstSegment]
    let highlightedNodeID: String?

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let rect = CGRect(origin: .zero, size: size)

            for segment in segments {
                let isHighlighted = segment.node.stableID == highlightedNodeID
                let shape = RingSegmentShape(
                    startAngle: segment.startAngle,
                    endAngle: segment.endAngle,
                    innerRadiusFraction: segment.innerRadiusFraction,
                    outerRadiusFraction: segment.outerRadiusFraction
                )
                let path = shape.path(in: rect)
                context.opacity = isHighlighted ? 1 : segment.opacity
                context.fill(path, with: .color(segment.color))
                context.stroke(
                    path,
                    with: .color(isHighlighted ? StoragePalette.primaryText.opacity(0.72) : StoragePalette.segmentStroke),
                    lineWidth: isHighlighted ? 2.5 : 1
                )
            }
        }
        .drawingGroup()
    }
}

private struct ChartInteractionLayer: NSViewRepresentable {
    let segments: [SunburstSegment]
    @Binding var hoveredNodeID: String?
    var onHover: (StorageAnalysisNode?) -> Void
    var onSelect: (StorageAnalysisNode) -> Void

    func makeNSView(context: Context) -> ChartHitTestView {
        let view = ChartHitTestView()
        view.isHidden = false
        return view
    }

    func updateNSView(_ nsView: ChartHitTestView, context: Context) {
        nsView.segments = segments
        nsView.hoveredNodeID = $hoveredNodeID
        nsView.onHover = onHover
        nsView.onSelect = onSelect
    }
}

private final class ChartHitTestView: NSView {
    var segments: [SunburstSegment] = []
    var hoveredNodeID: Binding<String?>?
    var onHover: (StorageAnalysisNode?) -> Void = { _ in }
    var onSelect: (StorageAnalysisNode) -> Void = { _ in }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        setHoveredSegment(segment(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredSegment(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let segment = segment(at: convert(event.locationInWindow, from: nil)) else { return }
        hoveredNodeID?.wrappedValue = nil
        onHover(nil)
        onSelect(segment.node)
    }

    private func setHoveredSegment(_ segment: SunburstSegment?) {
        let nextID = segment?.node.stableID
        guard hoveredNodeID?.wrappedValue != nextID else { return }
        hoveredNodeID?.wrappedValue = nextID
        onHover(segment?.node)
    }

    private func segment(at point: CGPoint) -> SunburstSegment? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let size = min(bounds.width, bounds.height)
        let radius = size / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distanceFraction = sqrt(dx * dx + dy * dy) / radius

        var angle = atan2(dy, dx)
        if angle < -.pi / 2 {
            angle += .pi * 2
        }

        return segments
            .sorted { $0.depth > $1.depth }
            .first { segment in
                distanceFraction >= segment.innerRadiusFraction &&
                distanceFraction <= segment.outerRadiusFraction &&
                angle >= segment.startAngle.radians &&
                angle <= segment.endAngle.radians
            }
    }
}

private struct SunburstSegment: Identifiable {
    let id: String
    let node: StorageAnalysisNode
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusFraction: CGFloat
    let outerRadiusFraction: CGFloat
    let color: Color
    let opacity: Double
    let depth: Int
}

private enum SunburstLayout {
    private static let maxReadableDepth = 8
    private static let maxSegments = 320
    private static let maxChildrenPerNode = 28
    private static let innerRadius: CGFloat = 0.30
    private static let outerRadius: CGFloat = 0.96
    private static let minimumRingWidth: CGFloat = 0.052

    static func segments(for root: StorageAnalysisNode) -> [SunburstSegment] {
        var output: [SunburstSegment] = []
        let visibleDepth = max(1, min(maxReadableDepth, scannedDepth(of: root)))
        let ringWidth = max(
            minimumRingWidth,
            (outerRadius - innerRadius) / CGFloat(visibleDepth)
        )

        appendChildren(
            of: root,
            start: -.pi / 2,
            end: .pi * 1.5,
            depth: 1,
            maxDepth: visibleDepth,
            ringWidth: ringWidth,
            rootIndex: 0,
            output: &output
        )
        return output
    }

    private static func appendChildren(
        of node: StorageAnalysisNode,
        start: Double,
        end: Double,
        depth: Int,
        maxDepth: Int,
        ringWidth: CGFloat,
        rootIndex: Int,
        output: inout [SunburstSegment]
    ) {
        guard depth <= maxDepth, output.count < maxSegments else { return }

        let children = visibleChildren(of: node)
        guard !children.isEmpty else { return }

        let total = max(children.reduce(Int64(0)) { $0 + $1.bytes }, 1)
        var cursor = start

        for (index, child) in children.enumerated() where output.count < maxSegments {
            let span = (end - start) * (Double(max(child.bytes, 1)) / Double(total))
            guard span > 0.003 else { continue }

            let childEnd = cursor + span
            let paletteIndex = depth == 1 ? index : rootIndex
            let inner = innerRadius + ringWidth * CGFloat(depth - 1)
            let outer = min(outerRadius, inner + ringWidth * 0.92)

            output.append(
                SunburstSegment(
                    id: "\(child.stableID)-\(depth)-\(String(format: "%.5f", cursor))",
                    node: child,
                    startAngle: .radians(cursor),
                    endAngle: .radians(childEnd),
                    innerRadiusFraction: inner,
                    outerRadiusFraction: outer,
                    color: StoragePalette.segmentColor(
                        index: paletteIndex,
                        depth: depth,
                        synthetic: child.synthetic
                    ),
                    opacity: max(0.55, 1.0 - Double(depth) * 0.06),
                    depth: depth
                )
            )

            appendChildren(
                of: child,
                start: cursor,
                end: childEnd,
                depth: depth + 1,
                maxDepth: maxDepth,
                ringWidth: ringWidth,
                rootIndex: paletteIndex,
                output: &output
            )
            cursor = childEnd
        }
    }

    private static func scannedDepth(of node: StorageAnalysisNode) -> Int {
        let childrenWithScannedDescendants = visibleChildren(of: node)
            .filter { !$0.children.isEmpty }

        guard !childrenWithScannedDescendants.isEmpty else {
            return node.children.isEmpty ? 0 : 1
        }

        return 1 + (childrenWithScannedDescendants.map(scannedDepth).max() ?? 0)
    }

    private static func visibleChildren(of node: StorageAnalysisNode) -> [StorageAnalysisNode] {
        let children = node.children
            .filter { $0.bytes > 0 || !$0.children.isEmpty }
            .sorted { lhs, rhs in
                if lhs.bytes == rhs.bytes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.bytes > rhs.bytes
            }

        guard children.count > maxChildrenPerNode else { return children }

        let visible = Array(children.prefix(maxChildrenPerNode - 1))
        let hidden = children.dropFirst(maxChildrenPerNode - 1)
        let hiddenNode = StorageAnalysisNode(
            name: "smaller objects",
            path: node.path,
            bytes: hidden.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: hidden.reduce(0) { $0 + $1.fileCount },
            folderCount: hidden.reduce(0) { $0 + $1.folderCount },
            children: [],
            synthetic: true
        )
        return visible + [hiddenNode]
    }
}

private struct RingSegmentShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusFraction: CGFloat
    var outerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let radius = size / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let innerRadius = radius * innerRadiusFraction
        let outerRadius = radius * outerRadiusFraction
        let start = startAngle.radians + 0.002
        let end = max(start + 0.002, endAngle.radians - 0.002)

        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(start),
            endAngle: .radians(end),
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: innerRadius, angle: end))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(end),
            endAngle: .radians(start),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
