import Foundation

enum TreeItemKind: String, Sendable, Codable {
    case directory
    case file
    case symlink
    case missing

    var iconName: String {
        switch self {
        case .directory: "folder"
        case .file: "doc"
        case .symlink: "arrow.triangle.branch"
        case .missing: "questionmark.folder"
        }
    }
}

struct DirectoryTreeNode: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var path: String
    var kind: TreeItemKind
    var depth: Int
    var children: [DirectoryTreeNode]
    var childCount: Int
    var fileCount: Int
    var folderCount: Int
    var maxDepth: Int
    var modifiedAt: Date?
    var isHidden: Bool
    var isPackage: Bool
    var isTruncated: Bool

    var isDirectory: Bool {
        kind == .directory
    }
}

struct DirectoryTreeSnapshot: Equatable, Sendable {
    var root: DirectoryTreeNode
    var generatedAt: String
    var scannedEntries: Int
    var maxEntries: Int
    var isComplete: Bool
    var currentPath: String
    var missingPaths: [String]
    var truncated: Bool
}

struct TreeScanOptions: Equatable, Sendable {
    var maxDepth: Int = 1
    var textDepth: Int = 3
    var includeHidden = false
    var includePackages = false
    var maxEntries = 2000
}
