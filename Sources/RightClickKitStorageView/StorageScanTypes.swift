import Foundation
import RightClickKitCore

struct StorageScanProgress: Sendable, Equatable {
    var scannedBytes: Int64
    var scannedFiles: Int
    var scannedFolders: Int
    var completedBranches: Int
    var totalBranches: Int
    var activeBranches: Int
    var currentPath: String
    var isComplete: Bool

    static let empty = StorageScanProgress(
        scannedBytes: 0,
        scannedFiles: 0,
        scannedFolders: 0,
        completedBranches: 0,
        totalBranches: 0,
        activeBranches: 0,
        currentPath: "",
        isComplete: false
    )
}

struct StorageScanSnapshot: Sendable, Equatable {
    var report: StorageAnalysisReport
    var progress: StorageScanProgress
}

struct StorageLayerSnapshot: Sendable, Equatable {
    var node: StorageAnalysisNode
    var missingPaths: [String]
    var generatedAt: String
    var completedBranches: Int
    var totalBranches: Int
    var activeBranches: Int
    var currentPath: String
    var isComplete: Bool

    init(
        node: StorageAnalysisNode,
        missingPaths: [String],
        generatedAt: String,
        completedBranches: Int? = nil,
        totalBranches: Int? = nil,
        activeBranches: Int = 0,
        currentPath: String? = nil,
        isComplete: Bool = true
    ) {
        self.node = node
        self.missingPaths = missingPaths
        self.generatedAt = generatedAt
        self.completedBranches = completedBranches ?? node.children.filter { $0.bytes > 0 || $0.fileCount > 0 }.count
        self.totalBranches = totalBranches ?? node.children.count
        self.activeBranches = activeBranches
        self.currentPath = currentPath ?? node.path
        self.isComplete = isComplete
    }
}

struct StorageNodeScanSnapshot: Sendable, Equatable {
    var node: StorageAnalysisNode
    var completedBranches: Int
    var totalBranches: Int
    var activeBranches: Int
    var currentPath: String
    var isComplete: Bool

    init(
        node: StorageAnalysisNode,
        completedBranches: Int? = nil,
        totalBranches: Int? = nil,
        activeBranches: Int = 0,
        currentPath: String? = nil,
        isComplete: Bool = true
    ) {
        self.node = node
        self.completedBranches = completedBranches ?? node.children.filter { $0.bytes > 0 || $0.fileCount > 0 }.count
        self.totalBranches = totalBranches ?? node.children.count
        self.activeBranches = activeBranches
        self.currentPath = currentPath ?? node.path
        self.isComplete = isComplete
    }
}
