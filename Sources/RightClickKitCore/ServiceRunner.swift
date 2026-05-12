import Foundation

public struct ServiceRunner {
    public let config: RightClickKitConfig
    public let paths: RCKPaths

    public init(config: RightClickKitConfig, paths: RCKPaths = RCKPaths()) {
        self.config = config
        self.paths = paths
    }

    public func run(serviceID: String, arguments: [String]) throws -> Int32 {
        let store = ServiceStore(servicesDirectory: config.servicesURL)
        let service = try store.loadService(id: serviceID)
        let activityStore = ActivityStore(paths: paths)

        var items = arguments.filter { !$0.isEmpty }
        if items.isEmpty {
            items = finderSelection()
        }

        try FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
        let itemsFile = try writeItemsFile(serviceID: serviceID, items: items)
        let cwd = workingDirectory(for: items)

        var environment = ProcessInfo.processInfo.environment
        environment["RCK_SERVICE_ID"] = serviceID
        environment["RCK_ITEMS_FILE"] = itemsFile.path
        environment["RCK_HELPER"] = config.rckPath
        environment["RCK_REPOSITORY_ROOT"] = config.repositoryRoot
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")

        appendLog(serviceID: serviceID, text: "\n[\(Date())] run \(serviceID)\n")
        appendLog(serviceID: serviceID, text: "items: \(items.joined(separator: " | "))\n")
        let activity = try? activityStore.startRun(serviceID: serviceID, title: service.title, items: items)

        let result: (status: Int32, output: String)
        do {
            result = try ProcessRunner.runCapturing(
                service.shell,
                arguments: [service.scriptURL.path] + items,
                currentDirectory: cwd,
                environment: environment
            )
        } catch {
            _ = try? activityStore.finishRun(
                id: activity?.id,
                serviceID: serviceID,
                title: service.title,
                status: .failed,
                body: "Launch failed: \(error)"
            )
            throw error
        }

        if !result.output.isEmpty {
            appendLog(serviceID: serviceID, text: result.output)
            if !result.output.hasSuffix("\n") {
                appendLog(serviceID: serviceID, text: "\n")
            }
        }
        appendLog(serviceID: serviceID, text: "exit: \(result.status)\n")
        _ = try? activityStore.finishRun(
            id: activity?.id,
            serviceID: serviceID,
            title: service.title,
            status: result.status == 0 ? .review : .failed,
            body: result.status == 0 ? successBody(for: service.title, items: items) : failureBody(status: result.status, output: result.output)
        )
        return result.status
    }

    public func finderSelection() -> [String] {
        let script = """
        tell application "Finder"
          set selectedItems to selection
          if (count of selectedItems) is 0 then
            try
              set selectedItems to {target of front window as alias}
            on error
              set selectedItems to {}
            end try
          end if
          set outputPaths to {}
          repeat with selectedItem in selectedItems
            set end of outputPaths to POSIX path of (selectedItem as alias)
          end repeat
          set AppleScript's text item delimiters to linefeed
          return outputPaths as text
        end tell
        """

        do {
            let result = try ProcessRunner.runCapturing("/usr/bin/osascript", arguments: ["-e", script])
            guard result.status == 0 else { return [] }
            return result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private func workingDirectory(for items: [String]) -> URL? {
        guard let first = items.first else {
            return config.repositoryURL
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: first, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return URL(fileURLWithPath: first)
            }
            return URL(fileURLWithPath: first).deletingLastPathComponent()
        }

        return config.repositoryURL
    }

    private func writeItemsFile(serviceID: String, items: [String]) throws -> URL {
        let safeID = serviceID.replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rightclickkit-\(safeID)-\(UUID().uuidString).txt")
        try items.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func appendLog(serviceID: String, text: String) {
        let url = paths.logURL(serviceID: serviceID)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        guard let data = text.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url)
        else {
            return
        }

        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func successBody(for title: String, items: [String]) -> String {
        if items.isEmpty {
            return "\(title) finished."
        }
        if items.count == 1 {
            return "\(title) finished for \(items[0])."
        }
        return "\(title) finished for \(items.count) items."
    }

    private func failureBody(status: Int32, output: String) -> String {
        let trimmedOutput = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .suffix(3)
            .joined(separator: "\n")
        if trimmedOutput.isEmpty {
            return "Exited with status \(status)."
        }
        return "Exited with status \(status): \(trimmedOutput)"
    }
}
