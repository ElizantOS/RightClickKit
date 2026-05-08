import RightClickKitCore
import SwiftUI

struct StorageViewerRootView: View {
    @StateObject private var model: StorageScanModel

    init(request: StorageViewerRequest) {
        _model = StateObject(wrappedValue: StorageScanModel(request: request))
    }

    var body: some View {
        Group {
            switch model.phase {
            case let .scanning(title):
                StorageScanningView(title: title)
            case let .displaying(snapshot):
                StorageViewerView(
                    snapshot: snapshot,
                    loadingPaths: model.loadingPaths,
                    scanningProgress: model.scanningProgress,
                    expandedPaths: model.expandedPaths,
                    backgroundScanningPaused: model.backgroundScanningPaused,
                    onExpand: model.expand,
                    onToggleBackgroundScan: model.toggleBackgroundScanning,
                    onStopBackgroundScan: model.stopBackgroundScanning
                )
            case let .failed(message):
                StorageViewerErrorView(message: message)
            }
        }
        .task {
            model.start()
        }
    }
}

struct StorageViewerView: View {
    let snapshot: StorageScanSnapshot
    let loadingPaths: Set<String>
    let scanningProgress: [String: StorageNodeScanSnapshot]
    let expandedPaths: Set<String>
    let backgroundScanningPaused: Bool
    var onExpand: (StorageAnalysisNode) -> Void
    var onToggleBackgroundScan: () -> Void
    var onStopBackgroundScan: () -> Void
    @State private var selectedPath: [String] = []
    @State private var detailPath: [String] = []
    @State private var previewPath: [String]?

    private var report: StorageAnalysisReport {
        snapshot.report
    }

    private var displayNode: StorageAnalysisNode {
        if let previewPath, let node = node(at: previewPath, in: report.root) {
            return node
        }
        return node(at: detailPath, in: report.root) ?? selectedNode
    }

    private var selectedNode: StorageAnalysisNode {
        node(at: selectedPath, in: report.root) ?? report.root
    }

    var body: some View {
        RCKGlassGroup(spacing: 14) {
            HStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(report: report, progress: snapshot.progress, selectedNode: selectedNode)

                    SunburstChartView(
                        root: report.root,
                        selectedNode: selectedNode,
                        onHover: hoverFromChart,
                        onSelect: selectFromChart,
                        onBack: popSelection
                    )
                        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
                }
                .layoutPriority(1)

                StorageInspectorView(
                    report: report,
                    progress: snapshot.progress,
                    selectedNode: selectedNode,
                    node: displayNode,
                    loadingPaths: loadingPaths,
                    scanningProgress: scanningProgress,
                    expandedPaths: expandedPaths,
                    backgroundScanningPaused: backgroundScanningPaused,
                    onSelect: selectFromList,
                    onExpand: onExpand,
                    onPreviewPath: previewFromList,
                    onToggleBackgroundScan: onToggleBackgroundScan,
                    onStopBackgroundScan: onStopBackgroundScan
                )
                .frame(width: 370)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .foregroundStyle(StoragePalette.primaryText)
    }

    private func selectFromChart(_ node: StorageAnalysisNode) {
        if let path = path(to: node.stableID, in: report.root) {
            detailPath = path
            previewPath = nil
            if !node.synthetic, node.folderCount > 0 {
                selectedPath = path
                onExpand(node)
            } else if !node.children.isEmpty {
                selectedPath = path
            }
        }
    }

    private func hoverFromChart(_ node: StorageAnalysisNode?) {
        guard let node, let path = path(to: node.stableID, in: report.root) else {
            previewPath = nil
            return
        }
        previewPath = path
    }

    private func selectFromList(_ node: StorageAnalysisNode) {
        if let path = path(to: node.stableID, in: report.root) {
            detailPath = path
            previewPath = nil
            if !node.synthetic, node.folderCount > 0 {
                selectedPath = path
                onExpand(node)
            } else if !node.children.isEmpty {
                selectedPath = path
            }
        }
    }

    private func previewFromList(_ node: StorageAnalysisNode) {
        if let path = path(to: node.stableID, in: report.root) {
            previewPath = path
        }
    }

    private func popSelection() {
        guard !selectedPath.isEmpty else { return }
        selectedPath.removeLast()
        detailPath = selectedPath
        previewPath = nil
    }

    private func node(at path: [String], in root: StorageAnalysisNode) -> StorageAnalysisNode? {
        var node = root
        for id in path {
            guard let child = node.children.first(where: { $0.stableID == id }) else {
                return nil
            }
            node = child
        }
        return node
    }

    private func path(to id: String, in root: StorageAnalysisNode) -> [String]? {
        if root.stableID == id { return [] }

        for child in root.children {
            if child.stableID == id {
                return [child.stableID]
            }

            if let childPath = path(to: id, in: child) {
                return [child.stableID] + childPath
            }
        }

        return nil
    }
}

private struct HeaderView: View {
    let report: StorageAnalysisReport
    let progress: StorageScanProgress
    let selectedNode: StorageAnalysisNode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StoragePalette.blue)

                Text(selectedNode.name.isEmpty ? "Storage Analysis" : selectedNode.name)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 18)

                Text(StorageFormatter.bytes(selectedNode.bytes))
                    .font(.system(size: 22, weight: .medium))
                    .monospacedDigit()
            }

            Text(selectedNode.path)
                .font(.system(size: 12))
                .foregroundStyle(StoragePalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            ScanProgressBar(progress: progress)
                .padding(.top, 7)
        }
    }
}

private struct StorageInspectorView: View {
    let report: StorageAnalysisReport
    let progress: StorageScanProgress
    let selectedNode: StorageAnalysisNode
    let node: StorageAnalysisNode
    let loadingPaths: Set<String>
    let scanningProgress: [String: StorageNodeScanSnapshot]
    let expandedPaths: Set<String>
    let backgroundScanningPaused: Bool
    var onSelect: (StorageAnalysisNode) -> Void
    var onExpand: (StorageAnalysisNode) -> Void
    var onPreviewPath: (StorageAnalysisNode) -> Void
    var onToggleBackgroundScan: () -> Void
    var onStopBackgroundScan: () -> Void

    private var visibleChildren: [StorageAnalysisNode] {
        node.children
            .sorted { lhs, rhs in
                if lhs.bytes == rhs.bytes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.bytes > rhs.bytes
            }
    }

    private var emptyState: InspectorEmptyState? {
        guard visibleChildren.isEmpty else { return nil }
        if loadingPaths.contains(node.path) || scanningProgress[node.path] != nil {
            return .scanning
        }
        if node.folderCount > 0 {
            return expandedPaths.contains(node.path) ? .emptyFolder : .notLoaded
        }
        return .file
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(node.name.isEmpty ? "Selected Items" : node.name)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(node.path)
                    .font(.system(size: 12))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                MetricTile(value: StorageFormatter.bytes(node.bytes), label: "Size", icon: "chart.pie")
                MetricTile(value: StorageFormatter.count(node.fileCount), label: "Files", icon: "doc")
                MetricTile(value: StorageFormatter.count(node.folderCount), label: "Folders", icon: "folder")
            }

            if let progress = scanningProgress[node.path] {
                InlineNodeProgress(progress: progress)
            }

            Divider()
                .overlay(StoragePalette.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleChildren.prefix(14).enumerated()), id: \.element.stableID) { index, child in
                        Button {
                            onSelect(child)
                        } label: {
                            UsageRow(
                                node: child,
                                color: StoragePalette.segmentColor(index: index, depth: 1, synthetic: child.synthetic),
                                maxBytes: max(visibleChildren.map(\.bytes).max() ?? 1, 1),
                                isScanning: loadingPaths.contains(child.path)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(child.folderCount == 0 && child.children.isEmpty)
                        .onHover { hovering in
                            if hovering {
                                onPreviewPath(child)
                            }
                        }
                    }

                    if let emptyState {
                        InspectorEmptyStateView(
                            state: emptyState,
                            canScan: node.folderCount > 0 && !node.synthetic,
                            onScan: { onExpand(node) }
                        )
                    }

                    if !report.missingPaths.isEmpty {
                        MissingPathsView(paths: report.missingPaths)
                            .padding(.top, 8)
                    }
                }
                .padding(.trailing, 4)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Text(report.generatedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .lineLimit(1)

                Spacer()

                Text("RightClickKit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StoragePalette.blue)
            }

            ScanProgressFooter(
                progress: progress,
                backgroundScanningPaused: backgroundScanningPaused,
                onToggleBackgroundScan: onToggleBackgroundScan,
                onStopBackgroundScan: onStopBackgroundScan
            )
        }
        .padding(20)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private enum InspectorEmptyState {
    case scanning
    case notLoaded
    case emptyFolder
    case file

    var title: String {
        switch self {
        case .scanning:
            return "Scanning folder..."
        case .notLoaded:
            return "Contents not loaded yet"
        case .emptyFolder:
            return "No child items found"
        case .file:
            return "No folder breakdown"
        }
    }

    var detail: String {
        switch self {
        case .scanning:
            return "The child list will appear here as soon as sizes are available."
        case .notLoaded:
            return "Click the folder or use Scan Folder to load its child items."
        case .emptyFolder:
            return "This folder did not return visible child files or folders."
        case .file:
            return "Files are shown as leaf items in the chart."
        }
    }

    var icon: String {
        switch self {
        case .scanning:
            return "arrow.triangle.2.circlepath"
        case .notLoaded:
            return "folder.badge.plus"
        case .emptyFolder:
            return "folder"
        case .file:
            return "doc"
        }
    }
}

private struct InspectorEmptyStateView: View {
    let state: InspectorEmptyState
    let canScan: Bool
    var onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                if state == .scanning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(StoragePalette.blue)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: state.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StoragePalette.secondaryText)
                        .frame(width: 14)
                }

                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StoragePalette.primaryText)
            }

            Text(state.detail)
                .font(.system(size: 12))
                .foregroundStyle(StoragePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if state == .notLoaded, canScan {
                Button {
                    onScan()
                } label: {
                    Label("Scan Folder", systemImage: "bolt.horizontal.circle")
                }
                .rckGlassButton()
                .controlSize(.small)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}

private struct InlineNodeProgress: View {
    let progress: StorageNodeScanSnapshot

    private var fraction: Double {
        guard progress.totalBranches > 0 else { return progress.isComplete ? 1 : 0 }
        return min(1, max(0, Double(progress.completedBranches) / Double(progress.totalBranches)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StoragePalette.track)
                    Capsule()
                        .fill(StoragePalette.blue)
                        .frame(width: max(4, proxy.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 6)

            Text("\(progress.completedBranches)/\(max(progress.totalBranches, 1)) items · \(progress.currentPath)")
                .font(.system(size: 11))
                .foregroundStyle(StoragePalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct MetricTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StoragePalette.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(StoragePalette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UsageRow: View {
    let node: StorageAnalysisNode
    let color: Color
    let maxBytes: Int64
    let isScanning: Bool

    private var fraction: CGFloat {
        guard maxBytes > 0 else { return 0 }
        return max(0.02, CGFloat(Double(node.bytes) / Double(maxBytes)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Text(isScanning ? "Scanning" : StorageFormatter.bytes(node.bytes))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StoragePalette.track)
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 3)
    }
}

private struct ScanProgressBar: View {
    let progress: StorageScanProgress

    private var branchFraction: Double {
        guard progress.totalBranches > 0 else { return progress.isComplete ? 1 : 0 }
        return Double(progress.completedBranches) / Double(progress.totalBranches)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StoragePalette.track)
                    Capsule()
                        .fill(StoragePalette.blue)
                        .frame(width: max(4, proxy.size.width * CGFloat(branchFraction)))
                }
            }
            .frame(height: 6)

            HStack(spacing: 12) {
                Label(statusText, systemImage: progress.isComplete ? "checkmark.circle" : "bolt.horizontal.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(progress.isComplete ? StoragePalette.secondaryText : StoragePalette.blue)

                Text("\(StorageFormatter.count(progress.scannedFiles)) files")
                    .font(.system(size: 12))
                    .foregroundStyle(StoragePalette.secondaryText)

                Text(StorageFormatter.bytes(progress.scannedBytes))
                    .font(.system(size: 12))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .monospacedDigit()

                Spacer(minLength: 8)
            }
        }
    }

    private var statusText: String {
        if progress.isComplete {
            return "Scan complete"
        }
        return "\(progress.completedBranches)/\(max(progress.totalBranches, 1)) branches"
    }
}

private struct ScanProgressFooter: View {
    let progress: StorageScanProgress
    let backgroundScanningPaused: Bool
    var onToggleBackgroundScan: () -> Void
    var onStopBackgroundScan: () -> Void

    private var canControlBackground: Bool {
        !progress.isComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if !progress.isComplete {
                    ProgressView()
                        .controlSize(.small)
                        .tint(StoragePalette.blue)
                        .frame(width: 14, height: 14)
                }

                Text(progress.isComplete ? "Completed" : "Scanning")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(progress.isComplete ? StoragePalette.secondaryText : StoragePalette.blue)

                Spacer()

                Text("\(StorageFormatter.count(progress.scannedFolders)) folders")
                    .font(.system(size: 12))
                    .foregroundStyle(StoragePalette.secondaryText)
            }

            if !progress.currentPath.isEmpty {
                Text(progress.currentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if canControlBackground {
                HStack(spacing: 8) {
                    Button {
                        onToggleBackgroundScan()
                    } label: {
                        Label(
                            backgroundScanningPaused ? "Resume Background" : "Pause Background",
                            systemImage: backgroundScanningPaused ? "play.circle" : "pause.circle"
                        )
                    }
                    .rckGlassButton()

                    Button {
                        onStopBackgroundScan()
                    } label: {
                        Label("Stop Background", systemImage: "stop.circle")
                    }
                    .rckGlassButton()

                    Spacer(minLength: 0)
                }
                .controlSize(.small)
                .padding(.top, 5)
            }
        }
        .padding(.top, 2)
    }
}

private struct MissingPathsView: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Missing Paths", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))

            Text(paths.joined(separator: "\n"))
                .font(.system(size: 11))
                .lineLimit(4)
        }
        .foregroundStyle(StoragePalette.warning)
        .padding(11)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: false
        )
    }
}

private struct StorageScanningView: View {
    let title: String

    var body: some View {
        RCKGlassGroup(spacing: 12) {
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(StoragePalette.blue)

                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)

                Text("Scanning storage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StoragePalette.secondaryText)
            }
            .padding(28)
            .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(StoragePalette.primaryText)
    }
}

struct StorageViewerErrorView: View {
    let message: String

    var body: some View {
        RCKGlassGroup(spacing: 12) {
            VStack(spacing: 14) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(StoragePalette.warning)

                Text("Storage Analysis")
                    .font(.system(size: 24, weight: .semibold))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(StoragePalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(28)
            .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(StoragePalette.primaryText)
    }
}
