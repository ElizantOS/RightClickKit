import Foundation
import RightClickKitCore

enum LazyStorageScanner {
    private static let concurrentDuLimit = 3

    static func rootSnapshots(paths: [String], currentDirectory: String) -> AsyncStream<StorageLayerSnapshot> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let targets = targetURLs(from: paths, currentDirectory: URL(fileURLWithPath: currentDirectory))
                let generatedAt = timestamp()

                if targets.count == 1, let target = targets.first {
                    await streamSingleRoot(target, generatedAt: generatedAt, continuation: continuation)
                } else {
                    await streamMultipleRoots(targets, generatedAt: generatedAt, continuation: continuation)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func loadRoot(paths: [String], currentDirectory: String) async -> StorageLayerSnapshot {
        await Task.detached(priority: .userInitiated) {
            let targets = targetURLs(from: paths, currentDirectory: URL(fileURLWithPath: currentDirectory))
            let generatedAt = timestamp()
            return loadRootSync(targets: targets, generatedAt: generatedAt)
        }.value
    }

    static func loadChildren(for node: StorageAnalysisNode) async -> StorageAnalysisNode {
        await Task.detached(priority: .userInitiated) {
            loadChildrenSync(for: node)
        }.value
    }

    static func childSnapshots(for node: StorageAnalysisNode) -> AsyncStream<StorageNodeScanSnapshot> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await streamChildren(for: node, continuation: continuation)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey
    ]

    private static func streamSingleRoot(
        _ target: URL,
        generatedAt: String,
        continuation: AsyncStream<StorageLayerSnapshot>.Continuation
    ) async {
        let meta = metadata(target)
        guard meta.exists else {
            let root = StorageAnalysisNode(
                name: "Selected Items",
                path: target.path,
                bytes: 0,
                fileCount: 0,
                folderCount: 0,
                children: [],
                synthetic: false
            )
            continuation.yield(StorageLayerSnapshot(node: root, missingPaths: [target.path], generatedAt: generatedAt))
            return
        }

        guard meta.isDirectory, !meta.isSymbolicLink else {
            continuation.yield(StorageLayerSnapshot(
                node: sizedNode(for: target, knownBytes: nil),
                missingPaths: [],
                generatedAt: generatedAt
            ))
            return
        }

        let initial = initialDirectoryNode(for: target)
        continuation.yield(StorageLayerSnapshot(
            node: presented(initial),
            missingPaths: [],
            generatedAt: generatedAt,
            completedBranches: 0,
            totalBranches: initial.children.count,
            activeBranches: min(concurrentDuLimit, initial.children.count),
            currentPath: initial.path,
            isComplete: initial.children.isEmpty
        ))

        for await childSnapshot in directorySnapshots(for: initial) {
            continuation.yield(StorageLayerSnapshot(
                node: childSnapshot.node,
                missingPaths: [],
                generatedAt: generatedAt,
                completedBranches: childSnapshot.completedBranches,
                totalBranches: childSnapshot.totalBranches,
                activeBranches: childSnapshot.activeBranches,
                currentPath: childSnapshot.currentPath,
                isComplete: childSnapshot.isComplete
            ))
        }
    }

    private static func streamMultipleRoots(
        _ targets: [URL],
        generatedAt: String,
        continuation: AsyncStream<StorageLayerSnapshot>.Continuation
    ) async {
        var missingPaths: [String] = []
        let children = targets.compactMap { target -> StorageAnalysisNode? in
            guard metadata(target).exists else {
                missingPaths.append(target.path)
                return nil
            }
            return placeholderNode(for: target)
        }

        var root = StorageAnalysisNode(
            name: "Selected Items",
            path: children.map(\.path).joined(separator: "\n"),
            bytes: children.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            folderCount: children.reduce(0) { $0 + $1.folderCount },
            children: sorted(children),
            synthetic: false
        )
        continuation.yield(StorageLayerSnapshot(
            node: presented(root),
            missingPaths: missingPaths,
            generatedAt: generatedAt,
            completedBranches: 0,
            totalBranches: root.children.count,
            activeBranches: min(concurrentDuLimit, root.children.count),
            currentPath: root.path,
            isComplete: root.children.isEmpty
        ))

        await withTaskGroup(of: StorageAnalysisNode.self) { group in
            var iterator = root.children.enumerated().makeIterator()
            var running = 0

            func enqueue(_ child: StorageAnalysisNode) {
                running += 1
                group.addTask {
                    sizedNode(for: URL(fileURLWithPath: child.path), knownBytes: nil)
                }
            }

            while running < concurrentDuLimit, let item = iterator.next() {
                enqueue(item.element)
            }

            var completed = 0
            while running > 0, let updated = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                running -= 1
                completed += 1
                root.replaceDirectChild(updated)
                root = recomputed(root)

                if let item = iterator.next() {
                    enqueue(item.element)
                }

                continuation.yield(StorageLayerSnapshot(
                    node: presented(root),
                    missingPaths: missingPaths,
                    generatedAt: generatedAt,
                    completedBranches: completed,
                    totalBranches: root.children.count,
                    activeBranches: running,
                    currentPath: updated.path,
                    isComplete: false
                ))
            }

            continuation.yield(StorageLayerSnapshot(
                node: presented(root),
                missingPaths: missingPaths,
                generatedAt: generatedAt,
                completedBranches: root.children.count,
                totalBranches: root.children.count,
                activeBranches: 0,
                currentPath: root.path,
                isComplete: true
            ))
        }
    }

    private static func streamChildren(
        for node: StorageAnalysisNode,
        continuation: AsyncStream<StorageNodeScanSnapshot>.Continuation
    ) async {
        for await snapshot in directorySnapshots(for: node) {
            continuation.yield(snapshot)
        }
    }

    private static func directorySnapshots(for node: StorageAnalysisNode) -> AsyncStream<StorageNodeScanSnapshot> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let url = URL(fileURLWithPath: node.path)
                let meta = metadata(url)
                guard meta.exists, meta.isDirectory, !meta.isSymbolicLink else {
                    continuation.yield(StorageNodeScanSnapshot(node: node))
                    continuation.finish()
                    return
                }

                var current = initialDirectoryNode(for: url, original: node)
                continuation.yield(StorageNodeScanSnapshot(
                    node: presented(current),
                    completedBranches: 0,
                    totalBranches: current.children.count,
                    activeBranches: min(concurrentDuLimit, current.children.count),
                    currentPath: current.path,
                    isComplete: current.children.isEmpty
                ))

                await withTaskGroup(of: StorageAnalysisNode.self) { group in
                    var iterator = current.children.makeIterator()
                    var running = 0
                    var completed = 0

                    func enqueue(_ child: StorageAnalysisNode) {
                        running += 1
                        group.addTask {
                            sizedNode(for: URL(fileURLWithPath: child.path), knownBytes: nil)
                        }
                    }

                    while running < concurrentDuLimit, let child = iterator.next() {
                        enqueue(child)
                    }

                    while running > 0, let updated = await group.next() {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }

                        running -= 1
                        completed += 1
                        current.replaceDirectChild(updated)
                        current = recomputed(current)

                        if let child = iterator.next() {
                            enqueue(child)
                        }

                        continuation.yield(StorageNodeScanSnapshot(
                            node: presented(current),
                            completedBranches: completed,
                            totalBranches: current.children.count,
                            activeBranches: running,
                            currentPath: updated.path,
                            isComplete: false
                        ))
                    }

                    continuation.yield(StorageNodeScanSnapshot(
                        node: presented(current),
                        completedBranches: current.children.count,
                        totalBranches: current.children.count,
                        activeBranches: 0,
                        currentPath: current.path,
                        isComplete: true
                    ))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func loadRootSync(targets: [URL], generatedAt: String) -> StorageLayerSnapshot {
        if targets.count == 1, let target = targets.first {
            return loadSingleRoot(target, generatedAt: generatedAt)
        }

        var missingPaths: [String] = []
        let nodes = targets.compactMap { target -> StorageAnalysisNode? in
            guard metadata(target).exists else {
                missingPaths.append(target.path)
                return nil
            }
            return sizedNode(for: target, knownBytes: nil)
        }

        let root = StorageAnalysisNode(
            name: "Selected Items",
            path: nodes.map(\.path).joined(separator: "\n"),
            bytes: nodes.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: nodes.reduce(0) { $0 + $1.fileCount },
            folderCount: nodes.reduce(0) { $0 + $1.folderCount },
            children: sorted(nodes),
            synthetic: false
        )
        return StorageLayerSnapshot(node: root, missingPaths: missingPaths, generatedAt: generatedAt)
    }

    private static func initialRoot(paths targets: [URL], generatedAt: String) -> StorageLayerSnapshot? {
        if targets.count == 1, let target = targets.first {
            let meta = metadata(target)
            guard meta.exists else { return nil }

            if meta.isDirectory, !meta.isSymbolicLink {
                let children = capped(sorted(childURLs(of: target).map(placeholderNode)), parentPath: target.path)
                let root = StorageAnalysisNode(
                    name: displayName(target, meta: meta),
                    path: target.path,
                    bytes: children.reduce(Int64(0)) { $0 + $1.bytes },
                    fileCount: children.reduce(0) { $0 + $1.fileCount },
                    folderCount: 1 + children.reduce(0) { $0 + $1.folderCount },
                    children: children,
                    synthetic: false
                )
                return StorageLayerSnapshot(node: root, missingPaths: [], generatedAt: generatedAt)
            }

            return StorageLayerSnapshot(node: placeholderNode(for: target), missingPaths: [], generatedAt: generatedAt)
        }

        let nodes = targets.filter { metadata($0).exists }.map(placeholderNode)
        guard !nodes.isEmpty else { return nil }
        let root = StorageAnalysisNode(
            name: "Selected Items",
            path: nodes.map(\.path).joined(separator: "\n"),
            bytes: nodes.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: nodes.reduce(0) { $0 + $1.fileCount },
            folderCount: nodes.reduce(0) { $0 + $1.folderCount },
            children: sorted(nodes),
            synthetic: false
        )
        return StorageLayerSnapshot(node: root, missingPaths: [], generatedAt: generatedAt)
    }

    private static func loadSingleRoot(_ target: URL, generatedAt: String) -> StorageLayerSnapshot {
        let meta = metadata(target)
        guard meta.exists else {
            let root = StorageAnalysisNode(
                name: "Selected Items",
                path: target.path,
                bytes: 0,
                fileCount: 0,
                folderCount: 0,
                children: [],
                synthetic: false
            )
            return StorageLayerSnapshot(node: root, missingPaths: [target.path], generatedAt: generatedAt)
        }

        if meta.isDirectory, !meta.isSymbolicLink {
            let root = loadDirectoryLayer(url: target, includeSelf: true)
            return StorageLayerSnapshot(node: root, missingPaths: [], generatedAt: generatedAt)
        }

        return StorageLayerSnapshot(node: sizedNode(for: target, knownBytes: nil), missingPaths: [], generatedAt: generatedAt)
    }

    private static func loadChildrenSync(for node: StorageAnalysisNode) -> StorageAnalysisNode {
        let url = URL(fileURLWithPath: node.path)
        let meta = metadata(url)
        guard meta.exists, meta.isDirectory, !meta.isSymbolicLink else {
            return node
        }

        let layer = loadDirectoryLayer(url: url, includeSelf: true)
        return StorageAnalysisNode(
            name: node.name,
            path: node.path,
            bytes: layer.bytes,
            fileCount: layer.fileCount,
            folderCount: layer.folderCount,
            children: layer.children,
            synthetic: node.synthetic
        )
    }

    private static func loadDirectoryLayer(url: URL, includeSelf: Bool) -> StorageAnalysisNode {
        let meta = metadata(url)
        let sizeMap = duDepthOneBytes(for: url)
        let children = childURLs(of: url).map { child in
            sizedNode(for: child, knownBytes: sizeMap[child.standardizedFileURL.path])
        }
        let sortedChildren = capped(sorted(children), parentPath: url.path)

        let ownBytes = sizeMap[url.standardizedFileURL.path] ?? allocatedBytes(meta)
        let childBytes = sortedChildren.reduce(Int64(0)) { $0 + $1.bytes }
        let totalBytes = max(ownBytes, childBytes)
        let folderCount = (includeSelf ? 1 : 0) + sortedChildren.reduce(0) { $0 + $1.folderCount }

        return StorageAnalysisNode(
            name: displayName(url, meta: meta),
            path: url.path,
            bytes: totalBytes,
            fileCount: sortedChildren.reduce(0) { $0 + $1.fileCount },
            folderCount: folderCount,
            children: sortedChildren,
            synthetic: false
        )
    }

    private static func initialDirectoryNode(for url: URL, original: StorageAnalysisNode? = nil) -> StorageAnalysisNode {
        let meta = metadata(url)
        let children = sorted(childURLs(of: url).map(placeholderNode))

        return StorageAnalysisNode(
            name: original?.name ?? displayName(url, meta: meta),
            path: url.path,
            bytes: children.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            folderCount: 1 + children.reduce(0) { $0 + $1.folderCount },
            children: children,
            synthetic: original?.synthetic ?? false
        )
    }

    private static func sizedNode(for url: URL, knownBytes: Int64?) -> StorageAnalysisNode {
        let meta = metadata(url)
        let bytes = meta.isDirectory && !meta.isSymbolicLink
            ? knownBytes ?? duBytes(for: url) ?? allocatedBytes(meta)
            : allocatedBytes(meta)

        return StorageAnalysisNode(
            name: displayName(url, meta: meta),
            path: url.path,
            bytes: bytes,
            fileCount: meta.isDirectory && !meta.isSymbolicLink ? 0 : 1,
            folderCount: meta.isDirectory && !meta.isSymbolicLink ? 1 : 0,
            children: [],
            synthetic: false
        )
    }

    private static func placeholderNode(for url: URL) -> StorageAnalysisNode {
        let meta = metadata(url)
        let bytes = meta.isDirectory && !meta.isSymbolicLink ? 0 : allocatedBytes(meta)
        return StorageAnalysisNode(
            name: displayName(url, meta: meta),
            path: url.path,
            bytes: bytes,
            fileCount: meta.isDirectory && !meta.isSymbolicLink ? 0 : 1,
            folderCount: meta.isDirectory && !meta.isSymbolicLink ? 1 : 0,
            children: [],
            synthetic: false
        )
    }

    private static func childURLs(of directory: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )) ?? []

        let entries = children.map { url in
            StorageDirectoryEntry(url: url, metadata: metadata(url))
        }

        return entries.sorted { lhs, rhs in
            if lhs.metadata.isDirectory != rhs.metadata.isDirectory {
                return lhs.metadata.isDirectory
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }.map(\.url)
    }

    private static func duBytes(for url: URL) -> Int64? {
        guard !Task.isCancelled else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
        process.arguments = ["-n", "10", "/usr/bin/du", "-sk", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let output = String(data: data, encoding: .utf8),
            let kilobytesText = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first,
            let kilobytes = Int64(kilobytesText)
        else {
            return nil
        }
        return kilobytes * 1024
    }

    private static func duDepthOneBytes(for directory: URL) -> [String: Int64] {
        guard !Task.isCancelled else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
        process.arguments = ["-n", "10", "/usr/bin/du", "-k", "-d", "1", directory.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        guard process.terminationStatus == 0 else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var sizes: [String: Int64] = [:]
        for line in output.split(separator: "\n") {
            guard let tabIndex = line.firstIndex(of: "\t") else { continue }
            let kilobytesText = line[..<tabIndex]
            let pathText = line[line.index(after: tabIndex)...]
            guard let kilobytes = Int64(kilobytesText) else { continue }

            let path = URL(fileURLWithPath: String(pathText)).standardizedFileURL.path
            sizes[path] = kilobytes * 1024
        }

        return sizes
    }

    private static func metadata(_ url: URL) -> StorageItemMetadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let values = try? url.resourceValues(forKeys: resourceKeys)

        return StorageItemMetadata(
            exists: exists,
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: values?.isSymbolicLink == true,
            fileSize: values?.fileSize ?? 0,
            fileAllocatedSize: values?.fileAllocatedSize ?? 0,
            totalFileAllocatedSize: values?.totalFileAllocatedSize ?? 0
        )
    }

    private static func allocatedBytes(_ meta: StorageItemMetadata) -> Int64 {
        Int64(
            meta.totalFileAllocatedSize != 0 ? meta.totalFileAllocatedSize :
            meta.fileAllocatedSize != 0 ? meta.fileAllocatedSize :
            meta.fileSize
        )
    }

    private static func displayName(_ url: URL, meta: StorageItemMetadata) -> String {
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return name + (meta.isDirectory && !meta.isSymbolicLink ? "/" : "")
    }

    private static func sorted(_ nodes: [StorageAnalysisNode]) -> [StorageAnalysisNode] {
        nodes.sorted { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        }
    }

    private static func recomputed(_ node: StorageAnalysisNode) -> StorageAnalysisNode {
        let sortedChildren = sorted(node.children)
        return StorageAnalysisNode(
            name: node.name,
            path: node.path,
            bytes: sortedChildren.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: sortedChildren.reduce(0) { $0 + $1.fileCount },
            folderCount: 1 + sortedChildren.reduce(0) { $0 + $1.folderCount },
            children: sortedChildren,
            synthetic: node.synthetic
        )
    }

    private static func presented(_ node: StorageAnalysisNode) -> StorageAnalysisNode {
        StorageAnalysisNode(
            name: node.name,
            path: node.path,
            bytes: node.bytes,
            fileCount: node.fileCount,
            folderCount: node.folderCount,
            children: capped(sorted(node.children), parentPath: node.path),
            synthetic: node.synthetic
        )
    }

    private static func capped(_ nodes: [StorageAnalysisNode], parentPath: String) -> [StorageAnalysisNode] {
        guard nodes.count > ReportGenerator.storageVisualMaxChildren else {
            return nodes
        }

        let visible = Array(nodes.prefix(ReportGenerator.storageVisualMaxChildren - 1))
        let hidden = nodes.dropFirst(ReportGenerator.storageVisualMaxChildren - 1)
        let hiddenNode = StorageAnalysisNode(
            name: "smaller objects",
            path: parentPath,
            bytes: hidden.reduce(Int64(0)) { $0 + $1.bytes },
            fileCount: hidden.reduce(0) { $0 + $1.fileCount },
            folderCount: hidden.reduce(0) { $0 + $1.folderCount },
            children: [],
            synthetic: true
        )
        return visible + [hiddenNode]
    }

    private static func targetURLs(from items: [String], currentDirectory: URL) -> [URL] {
        let values = items.filter { !$0.isEmpty }
        let rawTargets = values.isEmpty ? [currentDirectory.path] : values

        return rawTargets.map { value in
            let url = value.hasPrefix("/")
                ? URL(fileURLWithPath: value)
                : currentDirectory.appendingPathComponent(value)
            return url.standardizedFileURL
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

private struct StorageItemMetadata: Sendable {
    var exists: Bool
    var isDirectory: Bool
    var isSymbolicLink: Bool
    var fileSize: Int
    var fileAllocatedSize: Int
    var totalFileAllocatedSize: Int
}

private struct StorageDirectoryEntry: Sendable {
    var url: URL
    var metadata: StorageItemMetadata
}

private extension StorageAnalysisNode {
    mutating func replaceDirectChild(_ replacement: StorageAnalysisNode) {
        guard let index = children.firstIndex(where: { $0.path == replacement.path }) else { return }
        children[index] = replacement
    }
}
