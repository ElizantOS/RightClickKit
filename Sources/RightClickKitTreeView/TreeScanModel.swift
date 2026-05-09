import AppKit
import Foundation

@MainActor
final class TreeScanModel: ObservableObject {
    enum Phase {
        case scanning(title: String)
        case displaying(DirectoryTreeSnapshot)
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published var options = TreeScanOptions()
    @Published var query = ""

    private let request: TreeViewerRequest
    private var didStart = false
    private var scanTask: Task<Void, Never>?

    init(request: TreeViewerRequest) {
        self.request = request
        switch request {
        case let .scan(paths, _):
            self.phase = .scanning(title: Self.title(for: paths))
        case let .invalid(message):
            self.phase = .failed(message)
        }
    }

    deinit {
        scanTask?.cancel()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        rescan()
    }

    func rescan() {
        scanTask?.cancel()
        switch request {
        case let .scan(paths, currentDirectory):
            phase = .scanning(title: Self.title(for: paths))
            let options = options
            scanTask = Task {
                for await snapshot in TreeScanner.snapshots(
                    paths: paths,
                    currentDirectory: currentDirectory,
                    options: options
                ) {
                    guard !Task.isCancelled else { break }
                    phase = .displaying(snapshot)
                }
            }
        case let .invalid(message):
            phase = .failed(message)
        }
    }

    func reveal(_ node: DirectoryTreeNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    func copyPath(_ node: DirectoryTreeNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func openTerminal(_ node: DirectoryTreeNode) {
        let path = node.isDirectory ? node.path : URL(fileURLWithPath: node.path).deletingLastPathComponent().path
        let script = "tell application \"Terminal\" to do script \"cd \(shellQuoted(path))\""
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script])
    }

    func openInCode(_ node: DirectoryTreeNode) {
        let path = node.path
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/code") {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/local/bin/code"), arguments: [path])
        } else {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: [path])
        }
    }

    func exportTreeText(_ snapshot: DirectoryTreeSnapshot) {
        let text = DirectoryTreeExporter.text(snapshot.root)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func title(for paths: [String]) -> String {
        if paths.count == 1, let first = paths.first {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        if paths.isEmpty {
            return "Directory Tree"
        }
        return "\(paths.count) selected items"
    }
}

enum TreeViewerRequest {
    case scan(paths: [String], currentDirectory: String)
    case invalid(String)

    static func parse(arguments: [String]) -> TreeViewerRequest {
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

        return .invalid("No directory tree target was provided.")
    }
}

enum DirectoryTreeExporter {
    static func text(_ root: DirectoryTreeNode) -> String {
        var lines = [root.name]
        append(root.children, prefix: "", lines: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(_ nodes: [DirectoryTreeNode], prefix: String, lines: inout [String]) {
        for (index, node) in nodes.enumerated() {
            let isLast = index == nodes.count - 1
            let branch = isLast ? "└── " : "├── "
            lines.append(prefix + branch + node.name)
            append(node.children, prefix: prefix + (isLast ? "    " : "│   "), lines: &lines)
        }
    }
}
