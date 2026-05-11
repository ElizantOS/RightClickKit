import Foundation
import RightClickKitCore

struct RCKCLI {
    let arguments: [String]
    let paths = RCKPaths()

    func run() -> Int32 {
        do {
            guard let command = arguments.dropFirst().first else {
                printHelp()
                return 0
            }

            let rest = Array(arguments.dropFirst(2))
            switch command {
            case "install":
                try install(rest)
                return 0
            case "uninstall":
                try uninstall()
                return 0
            case "list":
                try list(rest)
                return 0
            case "run":
                return try runService(rest)
            case "logs":
                try logs(rest)
                return 0
            case "report":
                try report(rest)
                return 0
            case "action":
                try action(rest)
                return 0
            case "config":
                try config()
                return 0
            case "help", "--help", "-h":
                printHelp()
                return 0
            default:
                throw RightClickKitError.invalidValue("unknown command: \(command)", URL(fileURLWithPath: "."))
            }
        } catch {
            fputs("rck: \(error)\n", stderr)
            return 1
        }
    }

    private func install(_ args: [String]) throws {
        let repoRoot = optionValue("--repo", in: args) ?? FileManager.default.currentDirectoryPath
        let rckPath = optionValue("--rck", in: args) ?? executablePath()
        let config = RightClickKitConfig(repositoryRoot: URL(fileURLWithPath: repoRoot).standardized.path, rckPath: rckPath)
        try ConfigStore(paths: paths).save(config)

        let store = ServiceStore(servicesDirectory: config.servicesURL)
        let services = try store.loadServices()
        try store.materializeActionScripts(for: services)
        let installed = try WorkflowInstaller(paths: paths).install(services: services, rckPath: config.rckPath)
        print("Installed \(installed.count) workflow(s).")
        for url in installed {
            print("  \(url.path)")
        }
    }

    private func uninstall() throws {
        let removed = try WorkflowInstaller(paths: paths).uninstallManagedWorkflows()
        print("Removed \(removed.count) workflow(s).")
        for url in removed {
            print("  \(url.path)")
        }
    }

    private func list(_ args: [String]) throws {
        let config = try loadConfigOrCurrentDirectory(args)
        let services = try ServiceStore(servicesDirectory: config.servicesURL).loadServices()
        if services.isEmpty {
            print("No services found in \(config.servicesURL.path)")
            return
        }
        for service in services {
            let state = service.enabled ? "enabled" : "disabled"
            print("\(service.id)\t\(state)\t\(service.title)")
        }
    }

    private func runService(_ args: [String]) throws -> Int32 {
        guard let serviceID = args.first else {
            throw RightClickKitError.invalidValue("usage: rck run <service-id> [paths...]", URL(fileURLWithPath: "."))
        }
        let config = try ConfigStore(paths: paths).load()
        let runner = ServiceRunner(config: config, paths: paths)
        return try runner.run(serviceID: serviceID, arguments: Array(args.dropFirst()))
    }

    private func logs(_ args: [String]) throws {
        guard let serviceID = args.first else {
            print(paths.logDirectory.path)
            return
        }
        let url = paths.logURL(serviceID: serviceID)
        print(url.path)
    }

    private func report(_ args: [String]) throws {
        let shouldOpen = !args.contains("--no-open")
        let filteredArgs = args.filter { $0 != "--no-open" }

        guard let kind = filteredArgs.first else {
            throw RightClickKitError.invalidValue(
                "usage: rck report <directory-tree|storage-analysis> [--no-open] [paths...]",
                URL(fileURLWithPath: ".")
            )
        }

        let items = Array(filteredArgs.dropFirst())
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        switch kind {
        case "directory-tree":
            if shouldOpen {
                try openDirectoryTree(items: items, currentDirectory: currentDirectory)
                print("Directory Tree: opened native viewer")
            } else {
                let reportURL = try ReportGenerator.writeDirectoryTreeReport(for: items, currentDirectory: currentDirectory)
                print("Report: \(reportURL.path)")
            }
        case "storage-analysis":
            if shouldOpen {
                try openStorageAnalysis(items: items, currentDirectory: currentDirectory)
                print("Storage Analysis: opened native viewer")
            } else {
                let reportURL = try ReportGenerator.writeStorageAnalysisReport(for: items, currentDirectory: currentDirectory)
                print("Report: \(reportURL.path)")
            }
        default:
            throw RightClickKitError.invalidValue(
                "unknown report kind: \(kind)",
                URL(fileURLWithPath: ".")
            )
        }
    }

    private func action(_ args: [String]) throws {
        guard args.first == "run", let actionID = args.dropFirst().first else {
            throw RightClickKitError.invalidValue(
                "usage: rck action run <action-id> [paths...]",
                URL(fileURLWithPath: ".")
            )
        }

        let items = Array(args.dropFirst(2))
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        switch actionID {
        case NativeToolID.directoryTree.rawValue:
            try openDirectoryTree(items: items, currentDirectory: currentDirectory)
            print("Directory Tree: opened native viewer")
        case NativeToolID.storageAnalysis.rawValue:
            try openStorageAnalysis(items: items, currentDirectory: currentDirectory)
            print("Storage Analysis: opened native viewer")
        default:
            let config = try ConfigStore(paths: paths).load()
            let runner = ServiceRunner(config: config, paths: paths)
            let status = try runner.run(serviceID: actionID, arguments: items)
            if status != 0 {
                throw RightClickKitError.commandFailed("rck run \(actionID)", status)
            }
        }
    }

    private func config() throws {
        let config = try ConfigStore(paths: paths).load()
        let data = try JSONEncoder.pretty.encode(config)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func loadConfigOrCurrentDirectory(_ args: [String]) throws -> RightClickKitConfig {
        if let repoRoot = optionValue("--repo", in: args) {
            return RightClickKitConfig(
                repositoryRoot: URL(fileURLWithPath: repoRoot).standardized.path,
                rckPath: executablePath()
            )
        }

        if FileManager.default.fileExists(atPath: paths.configURL.path) {
            return try ConfigStore(paths: paths).load()
        }

        return RightClickKitConfig(
            repositoryRoot: FileManager.default.currentDirectoryPath,
            rckPath: executablePath()
        )
    }

    private func optionValue(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name) else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex else { return nil }
        return args[valueIndex]
    }

    private func executablePath() -> String {
        let raw = CommandLine.arguments[0]
        if raw.hasPrefix("/") {
            return raw
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(raw)
            .standardized
            .path
    }

    private func openReport(_ url: URL) throws {
        let textEditResult = try ProcessRunner.runCapturing(
            "/usr/bin/open",
            arguments: ["-a", "TextEdit", url.path]
        )
        if textEditResult.status == 0 {
            return
        }

        let fallbackResult = try ProcessRunner.runCapturing("/usr/bin/open", arguments: [url.path])
        if fallbackResult.status != 0 {
            throw RightClickKitError.commandFailed("open \(url.path)", fallbackResult.status)
        }
    }

    private func openDirectoryTree(items: [String], currentDirectory: URL) throws {
        let scanItems = items.isEmpty ? [currentDirectory.path] : items
        let viewerArguments = ["--scan", "--cwd", currentDirectory.path, "--"] + scanItems

        if let appURL = treeViewerAppURL() {
            let result = try ProcessRunner.runCapturing(
                "/usr/bin/open",
                arguments: ["-n", appURL.path, "--args"] + viewerArguments
            )
            if result.status == 0 {
                return
            }
        }

        let viewer = treeViewerExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: viewer) else {
            throw RightClickKitError.invalidValue(
                "Directory tree viewer not installed. Expected \(viewer)",
                currentDirectory
            )
        }
        try ProcessRunner.runDetached(viewer, arguments: viewerArguments)
    }

    private func openStorageAnalysis(items: [String], currentDirectory: URL) throws {
        let scanItems = items.isEmpty ? [currentDirectory.path] : items
        let viewerArguments = ["--scan", "--cwd", currentDirectory.path, "--"] + scanItems

        if let appURL = storageViewerAppURL() {
            let result = try ProcessRunner.runCapturing(
                "/usr/bin/open",
                arguments: ["-n", appURL.path, "--args"] + viewerArguments
            )
            if result.status == 0 {
                return
            }
        }

        let viewer = storageViewerExecutablePath()
        guard FileManager.default.isExecutableFile(atPath: viewer) else {
            throw RightClickKitError.invalidValue(
                "Storage viewer not installed. Expected \(viewer)",
                currentDirectory
            )
        }
        try ProcessRunner.runDetached(viewer, arguments: viewerArguments)
    }

    private func treeViewerExecutablePath() -> String {
        if let override = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_TREE_VIEWER"], !override.isEmpty {
            return override
        }

        return URL(fileURLWithPath: executablePath())
            .deletingLastPathComponent()
            .appendingPathComponent("RightClickKitTreeView")
            .path
    }

    private func storageViewerExecutablePath() -> String {
        if let override = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_STORAGE_VIEWER"], !override.isEmpty {
            return override
        }

        return URL(fileURLWithPath: executablePath())
            .deletingLastPathComponent()
            .appendingPathComponent("RightClickKitStorageView")
            .path
    }

    private func treeViewerAppURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_TREE_VIEWER_APP"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let installedURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/RightClickKit.app/Contents/Helpers/RightClickKitTreeView.app")
        if fileManager.fileExists(atPath: installedURL.path) {
            return installedURL
        }

        return nil
    }

    private func storageViewerAppURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_STORAGE_VIEWER_APP"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let installedURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/RightClickKit.app/Contents/Helpers/RightClickKitStorageView.app")
        if fileManager.fileExists(atPath: installedURL.path) {
            return installedURL
        }

        return nil
    }

    private func printHelp() {
        print("""
        RightClickKit CLI

        Usage:
          rck install [--repo PATH] [--rck PATH]
          rck uninstall
          rck list [--repo PATH]
          rck run <service-id> [paths...]
          rck logs [service-id]
          rck report <directory-tree|storage-analysis> [--no-open] [paths...]
          rck action run <action-id> [paths...]
          rck config
        """)
    }
}

exit(RCKCLI(arguments: CommandLine.arguments).run())
