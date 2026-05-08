import Foundation
import RightClickKitCore

enum StorageViewerRequest {
    case scan(paths: [String], currentDirectory: String)
    case report(URL)
    case invalid(String)

    static func parse(arguments: [String]) -> StorageViewerRequest {
        if arguments.first == "--scan" {
            var currentDirectory = FileManager.default.currentDirectoryPath
            var index = arguments.index(after: arguments.startIndex)

            while index < arguments.endIndex {
                let value = arguments[index]
                if value == "--" {
                    let paths = Array(arguments[arguments.index(after: index)...])
                    return .scan(paths: paths, currentDirectory: currentDirectory)
                }

                if value == "--cwd", arguments.index(after: index) < arguments.endIndex {
                    currentDirectory = arguments[arguments.index(after: index)]
                    index = arguments.index(index, offsetBy: 2)
                    continue
                }

                index = arguments.index(after: index)
            }

            return .scan(paths: [], currentDirectory: currentDirectory)
        }

        guard let path = arguments.first else {
            return .invalid("No storage target was provided.")
        }
        return .report(URL(fileURLWithPath: path))
    }
}

@MainActor
final class StorageScanModel: ObservableObject {
    private static let maxConcurrentExpansions = 2
    private static let maxAutomaticExpansionDepth = 10
    private static let maxAutomaticExpansionBacklog = 96

    enum Phase {
        case scanning(title: String)
        case displaying(StorageScanSnapshot)
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var loadingPaths: Set<String> = []
    @Published private(set) var scanningProgress: [String: StorageNodeScanSnapshot] = [:]
    @Published private(set) var expandedPaths: Set<String> = []

    private let request: StorageViewerRequest
    private var didStart = false
    private var autoExpandQueue: [StorageAnalysisNode] = []
    private var queuedAutoExpandPaths: Set<String> = []
    private var expandedCache: [String: StorageAnalysisNode] = [:]

    init(request: StorageViewerRequest) {
        self.request = request

        switch request {
        case let .scan(paths, _):
            self.phase = .scanning(title: Self.title(for: paths))
        case .report:
            self.phase = .scanning(title: "Opening report")
        case let .invalid(message):
            self.phase = .failed(message)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        switch request {
        case let .scan(paths, currentDirectory):
            phase = .scanning(title: Self.title(for: paths))
            Task {
                for await layer in LazyStorageScanner.rootSnapshots(paths: paths, currentDirectory: currentDirectory) {
                    let report = cachedReport(from: Self.report(for: layer))
                    let pendingExpansions = layer.isComplete ? autoExpandCandidates(from: report.root).count : 0
                    publish(
                        report: report,
                        currentPath: layer.currentPath,
                        completedBranches: layer.completedBranches,
                        totalBranches: layer.totalBranches,
                        localActiveBranches: layer.activeBranches,
                        localIsComplete: layer.isComplete,
                        pendingBranches: pendingExpansions
                    )

                    if layer.isComplete {
                        scheduleAutoExpand(from: report.root)
                    }
                }
            }

        case let .report(url):
            phase = .scanning(title: url.lastPathComponent)
            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        let data = try Data(contentsOf: url)
                        return try JSONDecoder().decode(StorageAnalysisReport.self, from: data)
                    }.value
                    phase = .displaying(Self.snapshot(for: report, currentPath: report.root.path))
                } catch {
                    phase = .failed("Could not open \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

        case let .invalid(message):
            phase = .failed(message)
        }
    }

    func expand(_ node: StorageAnalysisNode) {
        expand(node, automatic: false)
    }

    private func expand(_ node: StorageAnalysisNode, automatic: Bool) {
        guard !node.synthetic, node.folderCount > 0, !loadingPaths.contains(node.path) else { return }
        removeQueuedExpansion(for: node.path)
        if let cached = expandedCache[node.path] {
            expandedPaths.insert(node.path)
            publishCachedNode(cached, currentPath: node.path)
            drainAutoExpandQueue()
            return
        }
        if expandedPaths.contains(node.path) {
            drainAutoExpandQueue()
            return
        }

        expandedPaths.insert(node.path)
        loadingPaths.insert(node.path)
        refreshDisplayedProgress(currentPath: node.path, localIsComplete: false)

        Task {
            for await scanSnapshot in LazyStorageScanner.childSnapshots(for: node) {
                let expanded = scanSnapshot.node
                expandedCache[node.path] = expanded
                scanningProgress[node.path] = scanSnapshot
                guard case let .displaying(snapshot) = phase else { continue }
                var report = snapshot.report
                if report.root.stableID == expanded.stableID {
                    report.root = expanded
                } else {
                    report.root.replaceNode(expanded)
                }
                report = cachedReport(from: report)
                publish(
                    report: report,
                    currentPath: scanSnapshot.currentPath,
                    completedBranches: scanSnapshot.completedBranches,
                    totalBranches: scanSnapshot.totalBranches,
                    localActiveBranches: scanSnapshot.activeBranches,
                    localIsComplete: scanSnapshot.isComplete
                )
                if automatic {
                    scheduleAutoExpand(from: report.root)
                }
            }
            loadingPaths.remove(node.path)
            scanningProgress.removeValue(forKey: node.path)
            refreshDisplayedProgress(currentPath: node.path, localIsComplete: loadingPaths.isEmpty)
            drainAutoExpandQueue()
        }
    }

    private func publishCachedNode(_ node: StorageAnalysisNode, currentPath: String) {
        guard case let .displaying(snapshot) = phase else { return }
        var report = snapshot.report
        if report.root.stableID == node.stableID || report.root.path == node.path {
            report.root = node
        } else {
            report.root.replaceNode(node)
        }
        publish(
            report: cachedReport(from: report),
            currentPath: currentPath,
            completedBranches: snapshot.progress.completedBranches,
            totalBranches: snapshot.progress.totalBranches,
            localActiveBranches: 0,
            localIsComplete: loadingPaths.isEmpty
        )
    }

    private func scheduleAutoExpand(from root: StorageAnalysisNode) {
        var didEnqueue = false
        for node in autoExpandCandidates(from: root) where autoExpandQueue.count < Self.maxAutomaticExpansionBacklog {
            guard !queuedAutoExpandPaths.contains(node.path) else { continue }
            queuedAutoExpandPaths.insert(node.path)
            autoExpandQueue.append(node)
            didEnqueue = true
        }

        drainAutoExpandQueue()

        if didEnqueue {
            refreshDisplayedProgress(currentPath: root.path, localIsComplete: false)
        }
    }

    private func autoExpandCandidates(from root: StorageAnalysisNode) -> [StorageAnalysisNode] {
        root.autoExpandCandidates(maxDepth: Self.maxAutomaticExpansionDepth)
            .filter {
                !expandedPaths.contains($0.path) &&
                !loadingPaths.contains($0.path) &&
                !queuedAutoExpandPaths.contains($0.path)
            }
    }

    private func drainAutoExpandQueue() {
        while loadingPaths.count < Self.maxConcurrentExpansions, !autoExpandQueue.isEmpty {
            let node = autoExpandQueue.removeFirst()
            queuedAutoExpandPaths.remove(node.path)
            expand(node, automatic: true)
        }
    }

    private func removeQueuedExpansion(for path: String) {
        guard queuedAutoExpandPaths.remove(path) != nil else { return }
        autoExpandQueue.removeAll { $0.path == path }
    }

    private func publish(
        report: StorageAnalysisReport,
        currentPath: String,
        completedBranches: Int? = nil,
        totalBranches: Int? = nil,
        localActiveBranches: Int = 0,
        localIsComplete: Bool = true,
        pendingBranches: Int = 0
    ) {
        let activeBranches = localActiveBranches + loadingPaths.count + queuedAutoExpandPaths.count + pendingBranches
        let report = cachedReport(from: report)
        phase = .displaying(Self.snapshot(
            for: report,
            currentPath: currentPath,
            completedBranches: completedBranches,
            totalBranches: totalBranches,
            activeBranches: activeBranches,
            isComplete: localIsComplete && activeBranches == 0
        ))
    }

    private func refreshDisplayedProgress(
        currentPath: String,
        localIsComplete: Bool = true
    ) {
        guard case let .displaying(snapshot) = phase else { return }
        publish(
            report: snapshot.report,
            currentPath: currentPath,
            completedBranches: snapshot.progress.completedBranches,
            totalBranches: snapshot.progress.totalBranches,
            localActiveBranches: 0,
            localIsComplete: localIsComplete
        )
    }

    private func cachedReport(from report: StorageAnalysisReport) -> StorageAnalysisReport {
        var report = report
        for node in expandedCache.values.sorted(by: { $0.path.count < $1.path.count }) {
            if report.root.stableID == node.stableID || report.root.path == node.path {
                report.root = node
            } else {
                report.root.replaceNode(node)
            }
        }
        return report
    }

    private static func snapshot(
        for report: StorageAnalysisReport,
        currentPath: String,
        completedBranches: Int? = nil,
        totalBranches: Int? = nil,
        activeBranches: Int = 0,
        isComplete: Bool = true
    ) -> StorageScanSnapshot {
        StorageScanSnapshot(
            report: report,
            progress: StorageScanProgress(
                scannedBytes: report.root.bytes,
                scannedFiles: report.root.fileCount,
                scannedFolders: report.root.folderCount,
                completedBranches: completedBranches ?? report.root.children.filter { $0.bytes > 0 || $0.fileCount > 0 }.count,
                totalBranches: totalBranches ?? report.root.children.count,
                activeBranches: activeBranches,
                currentPath: currentPath,
                isComplete: isComplete
            )
        )
    }

    private static func snapshot(for layer: StorageLayerSnapshot) -> StorageScanSnapshot {
        snapshot(
            for: report(for: layer),
            currentPath: layer.currentPath,
            completedBranches: layer.completedBranches,
            totalBranches: layer.totalBranches,
            activeBranches: layer.activeBranches,
            isComplete: layer.isComplete
        )
    }

    private static func report(for layer: StorageLayerSnapshot) -> StorageAnalysisReport {
        StorageAnalysisReport(
            generatedAt: layer.generatedAt,
            root: layer.node,
            missingPaths: layer.missingPaths
        )
    }

    private static func title(for paths: [String]) -> String {
        if paths.count == 1, let first = paths.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }

        if paths.isEmpty {
            return "Selected Items"
        }

        return "\(paths.count) selected items"
    }
}

private extension StorageAnalysisNode {
    mutating func replaceNode(_ replacement: StorageAnalysisNode) {
        for index in children.indices {
            if children[index].stableID == replacement.stableID || children[index].path == replacement.path {
                children[index] = replacement
                return
            }

            children[index].replaceNode(replacement)
        }
    }

    func autoExpandCandidates(maxDepth: Int) -> [StorageAnalysisNode] {
        var output: [StorageAnalysisNode] = []
        collectAutoExpandCandidates(into: &output, depth: 0, maxDepth: maxDepth)
        return output.sorted { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        }
    }

    private func collectAutoExpandCandidates(
        into output: inout [StorageAnalysisNode],
        depth: Int,
        maxDepth: Int
    ) {
        guard depth < maxDepth else { return }

        for child in children {
            if !child.synthetic, child.folderCount > 0, child.children.isEmpty, child.bytes > 0 {
                output.append(child)
            }

            if !child.children.isEmpty {
                child.collectAutoExpandCandidates(into: &output, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }
}
