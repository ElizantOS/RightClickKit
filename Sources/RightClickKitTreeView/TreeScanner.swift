import Foundation

enum TreeScanner {
    static func snapshots(
        paths: [String],
        currentDirectory: String,
        options: TreeScanOptions
    ) -> AsyncStream<DirectoryTreeSnapshot> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let scanner = DirectoryScanner(options: options)
                for await snapshot in scanner.scan(paths: paths, currentDirectory: currentDirectory) {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func loadChildren(
        for node: DirectoryTreeNode,
        options: TreeScanOptions
    ) async -> DirectoryTreeNode {
        await Task.detached(priority: .userInitiated) {
            DirectoryChildLoader(options: options).loadChildren(for: node)
        }.value
    }
}

private final class DirectoryChildLoader: @unchecked Sendable {
    private let options: TreeScanOptions

    init(options: TreeScanOptions) {
        self.options = options
    }

    func loadChildren(for node: DirectoryTreeNode) -> DirectoryTreeNode {
        let url = URL(fileURLWithPath: node.path)
        let meta = metadata(url, includeChildCount: true)
        guard meta.exists, meta.isDirectory, !meta.isSymbolicLink else {
            return node
        }

        if meta.isPackage, !options.includePackages {
            var replacement = node
            replacement.childCount = meta.childCount
            replacement.modifiedAt = meta.modifiedAt
            replacement.isPackage = true
            return replacement
        }

        let childDepth = node.depth + 1
        let children = childURLs(of: url)
            .filter { options.includeHidden || !isHidden($0) }
            .map { childNode(for: $0, depth: childDepth) }
            .filter { $0.kind != .missing }

        var replacement = node
        replacement.children = children
        replacement.childCount = children.count
        replacement.fileCount = children.reduce(0) { $0 + $1.fileCount }
        replacement.folderCount = 1 + children.reduce(0) { $0 + $1.folderCount }
        replacement.maxDepth = children.map(\.maxDepth).max() ?? node.depth
        replacement.modifiedAt = meta.modifiedAt
        replacement.isPackage = meta.isPackage
        replacement.isTruncated = false
        return replacement
    }

    private func childNode(for url: URL, depth: Int) -> DirectoryTreeNode {
        let meta = metadata(url, includeChildCount: true)

        let kind: TreeItemKind
        if !meta.exists {
            kind = .missing
        } else if meta.isSymbolicLink {
            kind = .symlink
        } else if meta.isDirectory {
            kind = .directory
        } else {
            kind = .file
        }

        return DirectoryTreeNode(
            id: stableID(url, depth: depth),
            name: displayName(url, meta: meta),
            path: url.path,
            kind: kind,
            depth: depth,
            children: [],
            childCount: kind == .directory ? meta.childCount : 0,
            fileCount: kind == .file || kind == .symlink ? 1 : 0,
            folderCount: kind == .directory ? 1 : 0,
            maxDepth: depth,
            modifiedAt: meta.modifiedAt,
            isHidden: isHidden(url),
            isPackage: meta.isPackage,
            isTruncated: false
        )
    }

    private func childURLs(of directory: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        )) ?? []

        let entries = children.map { TreeDirectoryEntry(url: $0, metadata: metadata($0)) }
        return entries.sorted { lhs, rhs in
            if lhs.metadata.isDirectory != rhs.metadata.isDirectory {
                return lhs.metadata.isDirectory
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }.map(\.url)
    }

    private func metadata(_ url: URL, includeChildCount: Bool = false) -> TreeMetadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let values = try? url.resourceValues(forKeys: Self.resourceKeys)
        let childCount: Int
        if includeChildCount, isDirectory.boolValue {
            childCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
        } else {
            childCount = 0
        }

        return TreeMetadata(
            exists: exists,
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: values?.isSymbolicLink == true,
            isPackage: values?.isPackage == true,
            modifiedAt: values?.contentModificationDate,
            childCount: childCount
        )
    }

    private func displayName(_ url: URL, meta: TreeMetadata) -> String {
        if url.path == "/" {
            return "/"
        }
        let base = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return meta.isDirectory && !meta.isSymbolicLink ? base + "/" : base
    }

    private func stableID(_ url: URL, depth: Int) -> String {
        "\(url.standardizedFileURL.path)|\(depth)"
    }

    private func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .contentModificationDateKey
    ]
}

private final class DirectoryScanner: @unchecked Sendable {
    private let options: TreeScanOptions
    private let generatedAt: String
    private var scannedEntries = 0
    private var truncated = false
    private var missingPaths: [String] = []
    private var lastYield = Date.distantPast
    private var progressRoot: DirectoryTreeNode?

    init(options: TreeScanOptions) {
        self.options = options
        self.generatedAt = Self.timestamp()
    }

    func scan(paths: [String], currentDirectory: String) -> AsyncStream<DirectoryTreeSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                let targets = Self.targetURLs(
                    from: paths,
                    currentDirectory: URL(fileURLWithPath: currentDirectory)
                )
                progressRoot = initialRoot(for: targets)
                if let progressRoot {
                    continuation.yield(snapshot(root: progressRoot, currentPath: progressRoot.path, isComplete: false))
                }
                let root = await scanTargets(targets, continuation: continuation)
                continuation.yield(snapshot(root: root, currentPath: root.path, isComplete: true))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func scanTargets(
        _ targets: [URL],
        continuation: AsyncStream<DirectoryTreeSnapshot>.Continuation
    ) async -> DirectoryTreeNode {
        if targets.count == 1, let target = targets.first {
            return await scanNode(target, depth: 0, continuation: continuation)
        }

        var children: [DirectoryTreeNode] = []
        for target in targets {
            guard !Task.isCancelled else { break }
            children.append(await scanNode(target, depth: 1, continuation: continuation))
        }

        let existing = children.filter { $0.kind != .missing }
        return DirectoryTreeNode(
            id: "selected-items",
            name: "Selected Items",
            path: existing.map(\.path).joined(separator: "\n"),
            kind: .directory,
            depth: 0,
            children: existing,
            childCount: existing.count,
            fileCount: existing.reduce(0) { $0 + $1.fileCount },
            folderCount: existing.reduce(0) { $0 + $1.folderCount },
            maxDepth: existing.map(\.maxDepth).max() ?? 0,
            modifiedAt: nil,
            isHidden: false,
            isPackage: false,
            isTruncated: truncated
        )
    }

    private func scanNode(
        _ url: URL,
        depth: Int,
        continuation: AsyncStream<DirectoryTreeSnapshot>.Continuation
    ) async -> DirectoryTreeNode {
        guard scannedEntries < options.maxEntries else {
            truncated = true
            let node = omittedNode(parent: url, depth: depth, remainingCount: 1)
            recordProgress(node, currentPath: url.path, continuation: continuation)
            return node
        }

        scannedEntries += 1
        let meta = metadata(url)

        guard meta.exists else {
            missingPaths.append(url.path)
            let node = DirectoryTreeNode(
                id: stableID(url, depth: depth),
                name: displayName(url, meta: meta),
                path: url.path,
                kind: .missing,
                depth: depth,
                children: [],
                childCount: 0,
                fileCount: 0,
                folderCount: 0,
                maxDepth: depth,
                modifiedAt: nil,
                isHidden: isHidden(url),
                isPackage: false,
                isTruncated: false
            )
            recordProgress(node, currentPath: url.path, continuation: continuation)
            return node
        }

        let kind: TreeItemKind
        if meta.isSymbolicLink {
            kind = .symlink
        } else if meta.isDirectory {
            kind = .directory
        } else {
            kind = .file
        }

        guard kind == .directory, depth < options.maxDepth else {
            let node = DirectoryTreeNode(
                id: stableID(url, depth: depth),
                name: displayName(url, meta: meta),
                path: url.path,
                kind: kind,
                depth: depth,
                children: [],
                childCount: 0,
                fileCount: kind == .file || kind == .symlink ? 1 : 0,
                folderCount: kind == .directory ? 1 : 0,
                maxDepth: depth,
                modifiedAt: meta.modifiedAt,
                isHidden: isHidden(url),
                isPackage: meta.isPackage,
                isTruncated: false
            )
            recordProgress(node, currentPath: url.path, continuation: continuation)
            return node
        }

        if meta.isPackage, !options.includePackages {
            let packageMeta = metadata(url, includeChildCount: true)
            let node = DirectoryTreeNode(
                id: stableID(url, depth: depth),
                name: displayName(url, meta: meta),
                path: url.path,
                kind: .directory,
                depth: depth,
                children: [],
                childCount: packageMeta.childCount,
                fileCount: 0,
                folderCount: 1,
                maxDepth: depth,
                modifiedAt: meta.modifiedAt,
                isHidden: isHidden(url),
                isPackage: true,
                isTruncated: false
            )
            recordProgress(node, currentPath: url.path, continuation: continuation)
            return node
        }

        let candidates = childURLs(of: url).filter { options.includeHidden || !isHidden($0) }
        let childDepth = depth + 1
        let visibleLimit = max(0, options.maxEntries - scannedEntries)
        let visibleCandidates = Array(candidates.prefix(visibleLimit))
        var children = visibleCandidates.map { placeholderNode(for: $0, depth: childDepth) }

        if candidates.count > visibleCandidates.count {
            truncated = true
            children.append(omittedNode(
                parent: url,
                depth: childDepth,
                remainingCount: candidates.count - visibleCandidates.count
            ))
        }

        var partial = directoryNode(
            for: url,
            depth: depth,
            meta: meta,
            children: children,
            isTruncated: truncated
        )
        recordProgress(partial, currentPath: url.path, continuation: continuation, force: depth <= 1)

        for child in visibleCandidates {
            guard !Task.isCancelled else { break }
            guard scannedEntries < options.maxEntries else {
                truncated = true
                partial = directoryNode(
                    for: url,
                    depth: depth,
                    meta: meta,
                    children: children,
                    isTruncated: true
                )
                recordProgress(partial, currentPath: url.path, continuation: continuation, force: depth <= 1)
                break
            }

            let placeholderID = stableID(child, depth: childDepth)
            let scannedChild = await scanNode(child, depth: childDepth, continuation: continuation)
            if scannedChild.kind == .missing {
                children.removeAll { $0.id == placeholderID }
            } else if let index = children.firstIndex(where: { $0.id == placeholderID }) {
                children[index] = scannedChild
            } else {
                children.append(scannedChild)
            }
            partial = directoryNode(
                for: url,
                depth: depth,
                meta: meta,
                children: children,
                isTruncated: truncated
            )
            recordProgress(partial, currentPath: child.path, continuation: continuation)
        }

        let final = directoryNode(
            for: url,
            depth: depth,
            meta: meta,
            children: children,
            isTruncated: truncated
        )
        recordProgress(final, currentPath: url.path, continuation: continuation, force: depth <= 1)
        return final
    }

    private func directoryNode(
        for url: URL,
        depth: Int,
        meta: TreeMetadata,
        children: [DirectoryTreeNode],
        isTruncated: Bool
    ) -> DirectoryTreeNode {
        DirectoryTreeNode(
            id: stableID(url, depth: depth),
            name: displayName(url, meta: meta),
            path: url.path,
            kind: .directory,
            depth: depth,
            children: children,
            childCount: children.count,
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            folderCount: 1 + children.reduce(0) { $0 + $1.folderCount },
            maxDepth: children.map(\.maxDepth).max() ?? depth,
            modifiedAt: meta.modifiedAt,
            isHidden: isHidden(url),
            isPackage: meta.isPackage,
            isTruncated: isTruncated
        )
    }

    private func recordProgress(
        _ node: DirectoryTreeNode,
        currentPath: String,
        continuation: AsyncStream<DirectoryTreeSnapshot>.Continuation,
        force: Bool = false
    ) {
        if progressRoot?.id == node.id {
            progressRoot = node
        } else {
            _ = progressRoot?.replaceDescendant(node)
        }

        guard let progressRoot else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastYield) > 0.35 else { return }
        lastYield = now
        continuation.yield(snapshot(root: progressRoot, currentPath: currentPath, isComplete: false))
    }

    private func snapshot(
        root: DirectoryTreeNode,
        currentPath: String,
        isComplete: Bool
    ) -> DirectoryTreeSnapshot {
        DirectoryTreeSnapshot(
            root: root,
            generatedAt: generatedAt,
            scannedEntries: scannedEntries,
            maxEntries: options.maxEntries,
            isComplete: isComplete,
            currentPath: currentPath,
            missingPaths: missingPaths,
            truncated: truncated || root.isTruncated
        )
    }

    private func omittedNode(parent url: URL, depth: Int, remainingCount: Int) -> DirectoryTreeNode {
        DirectoryTreeNode(
            id: stableID(url, depth: depth) + "|omitted|\(remainingCount)",
            name: remainingCount == 1 ? "1 item omitted" : "\(remainingCount) items omitted",
            path: url.path,
            kind: .directory,
            depth: depth,
            children: [],
            childCount: remainingCount,
            fileCount: 0,
            folderCount: 0,
            maxDepth: depth,
            modifiedAt: nil,
            isHidden: false,
            isPackage: false,
            isTruncated: true
        )
    }

    private func initialRoot(for targets: [URL]) -> DirectoryTreeNode {
        if targets.count == 1, let target = targets.first {
            return placeholderNode(for: target, depth: 0)
        }

        let children = targets.map { placeholderNode(for: $0, depth: 1) }
        return DirectoryTreeNode(
            id: "selected-items",
            name: "Selected Items",
            path: children.map(\.path).joined(separator: "\n"),
            kind: .directory,
            depth: 0,
            children: children,
            childCount: children.count,
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            folderCount: children.reduce(0) { $0 + $1.folderCount },
            maxDepth: children.map(\.maxDepth).max() ?? 0,
            modifiedAt: nil,
            isHidden: false,
            isPackage: false,
            isTruncated: false
        )
    }

    private func placeholderNode(for url: URL, depth: Int) -> DirectoryTreeNode {
        let meta = metadata(url)
        let kind: TreeItemKind
        if !meta.exists {
            kind = .missing
        } else if meta.isSymbolicLink {
            kind = .symlink
        } else if meta.isDirectory {
            kind = .directory
        } else {
            kind = .file
        }

        return DirectoryTreeNode(
            id: stableID(url, depth: depth),
            name: displayName(url, meta: meta),
            path: url.path,
            kind: kind,
            depth: depth,
            children: [],
            childCount: meta.childCount,
            fileCount: kind == .file || kind == .symlink ? 1 : 0,
            folderCount: kind == .directory ? 1 : 0,
            maxDepth: depth,
            modifiedAt: meta.modifiedAt,
            isHidden: isHidden(url),
            isPackage: meta.isPackage,
            isTruncated: false
        )
    }

    private func childURLs(of directory: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        )) ?? []

        let entries = children.map { TreeDirectoryEntry(url: $0, metadata: metadata($0, includeChildCount: false)) }
        return entries.sorted { lhs, rhs in
            if lhs.metadata.isDirectory != rhs.metadata.isDirectory {
                return lhs.metadata.isDirectory
            }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }.map(\.url)
    }

    private func metadata(_ url: URL, includeChildCount: Bool = false) -> TreeMetadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let values = try? url.resourceValues(forKeys: Self.resourceKeys)
        let childCount: Int
        if includeChildCount, isDirectory.boolValue {
            childCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
        } else {
            childCount = 0
        }

        return TreeMetadata(
            exists: exists,
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: values?.isSymbolicLink == true,
            isPackage: values?.isPackage == true,
            modifiedAt: values?.contentModificationDate,
            childCount: childCount
        )
    }

    private func displayName(_ url: URL, meta: TreeMetadata) -> String {
        if url.path == "/" {
            return "/"
        }
        let base = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return meta.isDirectory && !meta.isSymbolicLink ? base + "/" : base
    }

    private func stableID(_ url: URL, depth: Int) -> String {
        "\(url.standardizedFileURL.path)|\(depth)"
    }

    private func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
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

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .contentModificationDateKey
    ]
}

private struct TreeMetadata: Sendable {
    var exists: Bool
    var isDirectory: Bool
    var isSymbolicLink: Bool
    var isPackage: Bool
    var modifiedAt: Date?
    var childCount: Int
}

private struct TreeDirectoryEntry: Sendable {
    var url: URL
    var metadata: TreeMetadata
}

private extension DirectoryTreeNode {
    mutating func replaceDescendant(_ replacement: DirectoryTreeNode) -> Bool {
        for index in children.indices {
            if children[index].id == replacement.id {
                children[index] = replacement
                return true
            }
            if children[index].replaceDescendant(replacement) {
                return true
            }
        }
        return false
    }
}
