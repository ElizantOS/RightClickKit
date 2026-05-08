import Foundation

public struct StorageAnalysisNode: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var bytes: Int64
    public var fileCount: Int
    public var folderCount: Int
    public var children: [StorageAnalysisNode]
    public var synthetic: Bool

    public init(
        name: String,
        path: String,
        bytes: Int64,
        fileCount: Int,
        folderCount: Int,
        children: [StorageAnalysisNode],
        synthetic: Bool
    ) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.children = children
        self.synthetic = synthetic
    }
}

public struct StorageAnalysisReport: Codable, Equatable, Sendable {
    public var generatedAt: String
    public var root: StorageAnalysisNode
    public var missingPaths: [String]

    public init(generatedAt: String, root: StorageAnalysisNode, missingPaths: [String]) {
        self.generatedAt = generatedAt
        self.root = root
        self.missingPaths = missingPaths
    }
}

public enum ReportGenerator {
    public static let treeMaxDepth = 8
    public static let treeMaxEntries = 4000
    public static let storageTopLimit = 25
    public static let storageVisualMaxDepth = 6
    public static let storageVisualMaxChildren = 30

    public static func writeDirectoryTreeReport(
        for items: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> URL {
        let targets = targetURLs(from: items, currentDirectory: currentDirectory)
        var state = TreeState()
        var lines = [
            "Directory Tree",
            "Generated: \(timestamp())",
            "Max depth: \(treeMaxDepth)",
            "Max entries: \(treeMaxEntries)",
            ""
        ]

        for target in targets {
            let kind = itemKind(target)
            guard kind.exists else {
                lines.append("Missing: \(target.path)")
                lines.append("")
                continue
            }

            if kind.isDirectory && !kind.isSymbolicLink {
                lines.append(target.path)
            } else {
                lines.append("\(target.path) (\(formatBytes(allocatedBytes(target))))")
            }

            if kind.isDirectory && !kind.isSymbolicLink {
                appendTreeChildren(of: target, prefix: "", depth: 1, lines: &lines, state: &state)
            }

            lines.append("")
            if state.truncated {
                break
            }
        }

        if state.truncated {
            lines.append("Report truncated after \(treeMaxEntries) entries.")
        }

        return try writeReport(named: "rightclickkit-directory-tree", lines: lines)
    }

    public static func writeStorageAnalysisReport(
        for items: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> URL {
        let report = storageAnalysisReport(for: items, currentDirectory: currentDirectory)
        return try writeJSONReport(named: "rightclickkit-storage-analysis", report: report)
    }

    public static func storageAnalysisReport(
        for items: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> StorageAnalysisReport {
        let targets = targetURLs(from: items, currentDirectory: currentDirectory)
        let generatedAt = timestamp()
        var roots: [StorageAnalysisNode] = []
        var missingPaths: [String] = []

        for target in targets {
            let kind = itemKind(target)
            guard kind.exists else {
                missingPaths.append(target.path)
                continue
            }

            roots.append(storageVisualNode(for: target, depth: 0))
        }

        let root: StorageAnalysisNode
        if roots.count == 1, let first = roots.first {
            root = first
        } else {
            root = StorageAnalysisNode(
                name: "Selected Items",
                path: roots.map(\.path).joined(separator: "\n"),
                bytes: roots.reduce(Int64(0)) { $0 + $1.bytes },
                fileCount: roots.reduce(0) { $0 + $1.fileCount },
                folderCount: roots.reduce(0) { $0 + $1.folderCount },
                children: roots,
                synthetic: false
            )
        }

        return StorageAnalysisReport(generatedAt: generatedAt, root: root, missingPaths: missingPaths)
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey
    ]

    private struct ItemKind {
        var exists: Bool
        var isDirectory: Bool
        var isSymbolicLink: Bool
    }

    private struct TreeState {
        var entries = 0
        var truncated = false
    }

    private struct SizedURL {
        var url: URL
        var bytes: Int64
    }

    private struct StorageStats {
        var totalBytes: Int64 = 0
        var fileCount = 0
        var folderCount = 0
        var largestFiles: [SizedURL] = []

        mutating func merge(_ other: StorageStats) {
            totalBytes += other.totalBytes
            fileCount += other.fileCount
            folderCount += other.folderCount
            largestFiles = Self.topFiles(largestFiles + other.largestFiles)
        }

        static func topFiles(_ files: [SizedURL]) -> [SizedURL] {
            Array(files.sorted { lhs, rhs in
                if lhs.bytes == rhs.bytes {
                    return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
                }
                return lhs.bytes > rhs.bytes
            }.prefix(storageTopLimit))
        }
    }

    private struct StorageBreakdown {
        var stats: StorageStats
        var childUsage: [SizedURL]
    }

    private static func storageVisualNode(for url: URL, depth: Int) -> StorageAnalysisNode {
        let kind = itemKind(url)
        let name = displayName(url)

        guard kind.exists else {
            return StorageAnalysisNode(
                name: name,
                path: url.path,
                bytes: 0,
                fileCount: 0,
                folderCount: 0,
                children: [],
                synthetic: false
            )
        }

        if !kind.isDirectory || kind.isSymbolicLink {
            return StorageAnalysisNode(
                name: name,
                path: url.path,
                bytes: allocatedBytes(url),
                fileCount: 1,
                folderCount: 0,
                children: [],
                synthetic: false
            )
        }

        if depth >= storageVisualMaxDepth {
            let stats = storageStats(for: url)
            return StorageAnalysisNode(
                name: name,
                path: url.path,
                bytes: stats.totalBytes,
                fileCount: stats.fileCount,
                folderCount: stats.folderCount,
                children: [],
                synthetic: false
            )
        }

        var children = childURLs(of: url)
            .map { storageVisualNode(for: $0, depth: depth + 1) }
            .filter { $0.bytes > 0 || !$0.children.isEmpty }
            .sorted { lhs, rhs in
                if lhs.bytes == rhs.bytes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.bytes > rhs.bytes
            }

        if children.count > storageVisualMaxChildren {
            let visible = Array(children.prefix(storageVisualMaxChildren - 1))
            let hidden = children.dropFirst(storageVisualMaxChildren - 1)
            let hiddenBytes = hidden.reduce(Int64(0)) { $0 + $1.bytes }
            let hiddenFileCount = hidden.reduce(0) { $0 + $1.fileCount }
            let hiddenFolderCount = hidden.reduce(0) { $0 + $1.folderCount }
            let hiddenNode = StorageAnalysisNode(
                name: "smaller objects",
                path: url.path,
                bytes: hiddenBytes,
                fileCount: hiddenFileCount,
                folderCount: hiddenFolderCount,
                children: [],
                synthetic: true
            )
            children = visible + [hiddenNode]
        }

        let totalBytes = children.reduce(Int64(0)) { $0 + $1.bytes }
        let fileCount = children.reduce(0) { $0 + $1.fileCount }
        let folderCount = children.reduce(1) { $0 + $1.folderCount }

        return StorageAnalysisNode(
            name: name,
            path: url.path,
            bytes: totalBytes,
            fileCount: fileCount,
            folderCount: folderCount,
            children: children,
            synthetic: false
        )
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

    private static func appendTreeChildren(
        of directory: URL,
        prefix: String,
        depth: Int,
        lines: inout [String],
        state: inout TreeState
    ) {
        guard !state.truncated else { return }

        if depth > treeMaxDepth {
            lines.append("\(prefix)... depth limit reached")
            return
        }

        let children = childURLs(of: directory)
        for (index, child) in children.enumerated() {
            guard state.entries < treeMaxEntries else {
                state.truncated = true
                return
            }

            let isLast = index == children.index(before: children.endIndex)
            let branch = isLast ? "`-- " : "|-- "
            let childPrefix = prefix + (isLast ? "    " : "|   ")
            let kind = itemKind(child)
            let marker = kind.isDirectory ? "/" : ""
            let size = kind.isDirectory ? "" : " (\(formatBytes(allocatedBytes(child))))"

            lines.append("\(prefix)\(branch)\(child.lastPathComponent)\(marker)\(size)")
            state.entries += 1

            if kind.isDirectory && !kind.isSymbolicLink {
                appendTreeChildren(of: child, prefix: childPrefix, depth: depth + 1, lines: &lines, state: &state)
            }

            if state.truncated {
                return
            }
        }
    }

    private static func appendDirectoryStorage(
        _ directory: URL,
        breakdown: StorageBreakdown,
        lines: inout [String]
    ) {
        lines.append("Path: \(directory.path)")
        lines.append("Total size: \(formatBytes(breakdown.stats.totalBytes))")
        lines.append("Files: \(breakdown.stats.fileCount)")
        lines.append("Folders: \(breakdown.stats.folderCount)")
        lines.append("")

        lines.append("Top-level usage:")
        if breakdown.childUsage.isEmpty {
            lines.append("  No readable children found.")
        } else {
            for child in breakdown.childUsage.prefix(storageTopLimit) {
                lines.append("  \(paddedSize(child.bytes))  \(displayName(child.url))")
            }
        }

        lines.append("")
        lines.append("Largest files:")
        if breakdown.stats.largestFiles.isEmpty {
            lines.append("  No readable files found.")
        } else {
            for file in breakdown.stats.largestFiles {
                lines.append("  \(paddedSize(file.bytes))  \(relativePath(file.url, under: directory))")
            }
        }

        lines.append("")
    }

    private static func storageBreakdown(for directory: URL) -> StorageBreakdown {
        var stats = StorageStats(folderCount: 1)
        var childUsage: [SizedURL] = []

        for child in childURLs(of: directory) {
            let childStats = storageStats(for: child)
            stats.merge(childStats)
            childUsage.append(SizedURL(url: child, bytes: childStats.totalBytes))
        }

        childUsage.sort { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        }

        return StorageBreakdown(stats: stats, childUsage: childUsage)
    }

    private static func storageStats(for url: URL) -> StorageStats {
        let kind = itemKind(url)
        guard kind.exists else { return StorageStats() }

        if kind.isDirectory && !kind.isSymbolicLink {
            var stats = StorageStats(folderCount: 1)
            for child in childURLs(of: url) {
                stats.merge(storageStats(for: child))
            }
            return stats
        }

        let bytes = allocatedBytes(url)
        return StorageStats(
            totalBytes: bytes,
            fileCount: 1,
            folderCount: 0,
            largestFiles: [SizedURL(url: url, bytes: bytes)]
        )
    }

    private static func childURLs(of directory: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: []
        )) ?? []

        return children.sorted { lhs, rhs in
            let lhsKind = itemKind(lhs)
            let rhsKind = itemKind(rhs)
            if lhsKind.isDirectory != rhsKind.isDirectory {
                return lhsKind.isDirectory
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private static func itemKind(_ url: URL) -> ItemKind {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))

        return ItemKind(
            exists: exists,
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: values?.isSymbolicLink == true
        )
    }

    private static func allocatedBytes(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        return Int64(
            values?.totalFileAllocatedSize ??
            values?.fileAllocatedSize ??
            values?.fileSize ??
            0
        )
    }

    private static func displayName(_ url: URL) -> String {
        let kind = itemKind(url)
        return url.lastPathComponent + (kind.isDirectory ? "/" : "")
    }

    private static func relativePath(_ url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(prefix.count))
    }

    private static func paddedSize(_ bytes: Int64) -> String {
        let text = formatBytes(bytes)
        return String(repeating: " ", count: max(0, 10 - text.count)) + text
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(max(bytes, 0))
        var unit = 0

        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }

        if unit == 0 {
            return "\(Int(size)) \(units[unit])"
        }
        return String(format: "%.1f %@", size, units[unit])
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func writeReport(named prefix: String, lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).txt")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func writeJSONReport(named prefix: String, report: StorageAnalysisReport) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: [.atomic])
        return url
    }
}
