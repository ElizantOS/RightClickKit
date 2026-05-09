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
    @Published private(set) var treeText = TreeTextSnapshot.loading("Preparing tree output")
    @Published var options = TreeScanOptions()
    @Published var query = ""

    private let request: TreeViewerRequest
    private var didStart = false
    private var scanTask: Task<Void, Never>?
    private var treeTextTask: Task<Void, Never>?

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
        treeTextTask?.cancel()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        rescan()
    }

    func rescan() {
        scanTask?.cancel()
        treeTextTask?.cancel()
        switch request {
        case let .scan(paths, currentDirectory):
            phase = .scanning(title: Self.title(for: paths))
            let options = options
            reloadTreeText(paths: paths, currentDirectory: currentDirectory, options: options)
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

    func reloadTreeText() {
        treeTextTask?.cancel()
        switch request {
        case let .scan(paths, currentDirectory):
            reloadTreeText(paths: paths, currentDirectory: currentDirectory, options: options)
        case .invalid:
            break
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
        let text = treeText.text ?? DirectoryTreeExporter.text(snapshot.root)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyTreeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func reloadTreeText(paths: [String], currentDirectory: String, options: TreeScanOptions) {
        treeText = .loading("Running tree")
        treeTextTask = Task {
            let snapshot = await TreeCommandRenderer.render(
                paths: paths,
                currentDirectory: currentDirectory,
                options: options
            )
            guard !Task.isCancelled else { return }
            treeText = snapshot
        }
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

enum TreeTextSnapshot {
    case loading(String)
    case ready(text: String, lineCount: Int, source: String)
    case failed(String)

    var text: String? {
        switch self {
        case let .ready(text, _, _):
            text
        case .loading, .failed:
            nil
        }
    }

    var title: String {
        switch self {
        case let .loading(message):
            message
        case let .ready(_, _, source):
            source
        case .failed:
            "Swift fallback"
        }
    }

    var lineCount: Int? {
        switch self {
        case let .ready(_, lineCount, _):
            lineCount
        case .loading, .failed:
            nil
        }
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

enum TreeCommandRenderer {
    static func render(paths: [String], currentDirectory: String, options: TreeScanOptions) async -> TreeTextSnapshot {
        await Task.detached(priority: .userInitiated) {
            guard let executable = treeExecutable() else {
                return .failed("The tree command was not found.")
            }

            let currentURL = URL(fileURLWithPath: currentDirectory)
            let targets = targetPaths(from: paths, currentDirectory: currentURL)
            var arguments = ["--charset", "unicode", "--noreport", "--dirsfirst", "-L", "\(max(1, options.textDepth))"]
            if options.includeHidden {
                arguments.append("-a")
            }
            arguments += targets

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.currentDirectoryURL = currentURL
            process.arguments = arguments

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = error.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    let trimmed = text.trimmingCharacters(in: .newlines)
                    return .ready(
                        text: trimmed,
                        lineCount: trimmed.split(whereSeparator: \.isNewline).count,
                        source: "tree -L \(max(1, options.textDepth))"
                    )
                }

                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failed(message?.isEmpty == false ? message! : "tree exited with status \(process.terminationStatus)")
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
    }

    private static func treeExecutable() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["RIGHTCLICKKIT_TREE_COMMAND"],
            "/opt/homebrew/bin/tree",
            "/usr/local/bin/tree",
            "/usr/bin/tree"
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func targetPaths(from items: [String], currentDirectory: URL) -> [String] {
        let values = items.filter { !$0.isEmpty }
        let rawTargets = values.isEmpty ? [currentDirectory.path] : values

        return rawTargets.map { value in
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value).standardizedFileURL.path
            }
            return currentDirectory.appendingPathComponent(value).standardizedFileURL.path
        }
    }
}
