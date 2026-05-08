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
    private static let maxAutomaticConcurrentExpansions = 1
    private static let maxAutomaticExpansionDepth = 6
    private static let maxAutomaticExpansionBacklog = 24
    private static let maxAutomaticExpansionsPerSession = 48
    private static let maxExpandedCacheEntries = 80
    private static let uiPublishIntervalNanoseconds: UInt64 = 350_000_000

    enum Phase {
        case scanning(title: String)
        case displaying(StorageScanSnapshot)
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var loadingPaths: Set<String> = []
    @Published private(set) var scanningProgress: [String: StorageNodeScanSnapshot] = [:]
    @Published private(set) var expandedPaths: Set<String> = []
    @Published private(set) var backgroundScanningPaused = false

    private let request: StorageViewerRequest
    private var didStart = false
    private var autoExpandQueue: [StorageAnalysisNode] = []
    private var queuedAutoExpandPaths: Set<String> = []
    private var automaticLoadingPaths: Set<String> = []
    private var automaticExpansionStarts = 0
    private var expandedCache: [String: StorageAnalysisNode] = [:]
    private var expandedCacheOrder: [String] = []
    private var progressByPath: [String: StorageNodeScanSnapshot] = [:]
    private var pendingDisplaySnapshot: StorageScanSnapshot?
    private var publishTask: Task<Void, Never>?
    private var rootScanTask: Task<Void, Never>?
    private var expansionTasks: [String: Task<Void, Never>] = [:]

    deinit {
        publishTask?.cancel()
        rootScanTask?.cancel()
        expansionTasks.values.forEach { $0.cancel() }
    }

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
            rootScanTask = Task {
                for await layer in LazyStorageScanner.rootSnapshots(paths: paths, currentDirectory: currentDirectory) {
                    guard !Task.isCancelled else { break }
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
            rootScanTask = Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        let data = try Data(contentsOf: url)
                        return try JSONDecoder().decode(StorageAnalysisReport.self, from: data)
                    }.value
                    display(Self.snapshot(for: report, currentPath: report.root.path), immediately: true)
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

    func toggleBackgroundScanning() {
        backgroundScanningPaused.toggle()
        if backgroundScanningPaused {
            refreshDisplayedProgress(currentPath: currentProgressPath, localIsComplete: false, immediately: true)
        } else {
            drainAutoExpandQueue()
            refreshDisplayedProgress(currentPath: currentProgressPath, localIsComplete: loadingPaths.isEmpty, immediately: true)
        }
    }

    func stopBackgroundScanning() {
        backgroundScanningPaused = true
        autoExpandQueue.removeAll()
        queuedAutoExpandPaths.removeAll()
        for path in automaticLoadingPaths {
            expansionTasks[path]?.cancel()
        }
        refreshDisplayedProgress(currentPath: currentProgressPath, localIsComplete: loadingPaths.isEmpty, immediately: true)
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

        if !automatic {
            backgroundScanningPaused = true
        }

        if expandedPaths.contains(node.path) {
            drainAutoExpandQueue()
            return
        }

        expandedPaths.insert(node.path)
        loadingPaths.insert(node.path)
        if automatic {
            automaticLoadingPaths.insert(node.path)
        }
        refreshDisplayedProgress(currentPath: node.path, localIsComplete: false, immediately: true)

        let task = Task {
            defer {
                loadingPaths.remove(node.path)
                automaticLoadingPaths.remove(node.path)
                expansionTasks.removeValue(forKey: node.path)
                progressByPath.removeValue(forKey: node.path)
                displayProgressNow()
                refreshDisplayedProgress(currentPath: node.path, localIsComplete: loadingPaths.isEmpty)
                drainAutoExpandQueue()
            }

            for await scanSnapshot in LazyStorageScanner.childSnapshots(for: node) {
                guard !Task.isCancelled else { break }
                let expanded = scanSnapshot.node
                storeExpandedNode(expanded)
                progressByPath[node.path] = scanSnapshot
                guard let snapshot = currentDisplaySnapshot else { continue }
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
                if automatic && scanSnapshot.isComplete {
                    scheduleAutoExpand(from: report.root)
                }
            }
        }
        expansionTasks[node.path] = task
    }

    private func publishCachedNode(_ node: StorageAnalysisNode, currentPath: String) {
        guard let snapshot = currentDisplaySnapshot else { return }
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
            localIsComplete: loadingPaths.isEmpty,
            immediate: true
        )
    }

    private func scheduleAutoExpand(from root: StorageAnalysisNode) {
        guard !backgroundScanningPaused else { return }
        guard automaticExpansionStarts < Self.maxAutomaticExpansionsPerSession else { return }

        var didEnqueue = false
        for node in autoExpandCandidates(from: root) where autoExpandQueue.count < Self.maxAutomaticExpansionBacklog {
            guard !queuedAutoExpandPaths.contains(node.path) else { continue }
            guard automaticExpansionStarts + queuedAutoExpandPaths.count < Self.maxAutomaticExpansionsPerSession else { break }
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
        guard !backgroundScanningPaused else { return }
        guard loadingPaths.subtracting(automaticLoadingPaths).isEmpty else { return }

        while automaticLoadingPaths.count < Self.maxAutomaticConcurrentExpansions,
              automaticExpansionStarts < Self.maxAutomaticExpansionsPerSession,
              !autoExpandQueue.isEmpty {
            let node = autoExpandQueue.removeFirst()
            queuedAutoExpandPaths.remove(node.path)
            automaticExpansionStarts += 1
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
        pendingBranches: Int = 0,
        immediate: Bool = false
    ) {
        let activeBranches = localActiveBranches + loadingPaths.count + queuedAutoExpandPaths.count + pendingBranches
        let report = cachedReport(from: report)
        let snapshot = Self.snapshot(
            for: report,
            currentPath: currentPath,
            completedBranches: completedBranches,
            totalBranches: totalBranches,
            activeBranches: activeBranches,
            isComplete: localIsComplete && activeBranches == 0
        )
        display(snapshot, immediately: immediate || currentDisplaySnapshot == nil || snapshot.progress.isComplete)
    }

    private func refreshDisplayedProgress(
        currentPath: String,
        localIsComplete: Bool = true,
        immediately: Bool = false
    ) {
        guard let snapshot = currentDisplaySnapshot else { return }
        publish(
            report: snapshot.report,
            currentPath: currentPath,
            completedBranches: snapshot.progress.completedBranches,
            totalBranches: snapshot.progress.totalBranches,
            localActiveBranches: 0,
            localIsComplete: localIsComplete,
            immediate: immediately
        )
    }

    private var currentDisplaySnapshot: StorageScanSnapshot? {
        if let pendingDisplaySnapshot {
            return pendingDisplaySnapshot
        }

        guard case let .displaying(snapshot) = phase else { return nil }
        return snapshot
    }

    private var currentProgressPath: String {
        currentDisplaySnapshot?.progress.currentPath ?? ""
    }

    private func display(_ snapshot: StorageScanSnapshot, immediately: Bool) {
        if immediately {
            publishTask?.cancel()
            publishTask = nil
            pendingDisplaySnapshot = nil
            scanningProgress = progressByPath
            phase = .displaying(snapshot)
            return
        }

        pendingDisplaySnapshot = snapshot
        guard publishTask == nil else { return }

        let delay = Self.uiPublishIntervalNanoseconds
        publishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flushPendingDisplay()
        }
    }

    private func flushPendingDisplay() {
        publishTask = nil
        guard let pendingDisplaySnapshot else { return }
        self.pendingDisplaySnapshot = nil
        scanningProgress = progressByPath
        phase = .displaying(pendingDisplaySnapshot)
    }

    private func displayProgressNow() {
        publishTask?.cancel()
        publishTask = nil
        if let pendingDisplaySnapshot {
            self.pendingDisplaySnapshot = nil
            scanningProgress = progressByPath
            phase = .displaying(pendingDisplaySnapshot)
        } else {
            scanningProgress = progressByPath
        }
    }

    private func storeExpandedNode(_ node: StorageAnalysisNode) {
        expandedCache[node.path] = node
        expandedCacheOrder.removeAll { $0 == node.path }
        expandedCacheOrder.append(node.path)
        trimExpandedCache()
    }

    private func trimExpandedCache() {
        var attempts = expandedCacheOrder.count
        while expandedCache.count > Self.maxExpandedCacheEntries, attempts > 0 {
            attempts -= 1
            let path = expandedCacheOrder.removeFirst()
            if loadingPaths.contains(path) {
                expandedCacheOrder.append(path)
                continue
            }
            expandedCache.removeValue(forKey: path)
        }
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
