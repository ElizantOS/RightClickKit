import Foundation
import RightClickKitCore

struct RCKCLI {
    let arguments: [String]
    let paths = RCKPaths()
    private let defaultPetID = "rck-dimo"
    private let builtInPetNames = [
        "rck-dimo": "RCK Dimo",
        "fireball": "Built-in Fireball"
    ]

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
            case "notify":
                try notify(rest)
                return 0
            case "pet":
                try pet(rest)
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

    private func notify(_ args: [String]) throws {
        guard let first = args.first else {
            throw RightClickKitError.invalidValue(
                "usage: rck notify <title> [--body TEXT] [--level info|success|warning|danger] [--status running|waiting|review|failed|done] [--source NAME] [--id ID] | list | read | clear",
                URL(fileURLWithPath: ".")
            )
        }

        let store = ActivityStore(paths: paths)
        switch first {
        case "list":
            let items = try store.list()
            for item in items {
                let unread = item.readAt == nil ? "unread" : "read"
                print("\(item.id)\t\(item.status.rawValue)\t\(item.level.rawValue)\t\(unread)\t\(item.title)")
            }
        case "read":
            try store.markAllRead()
            print("Marked all notifications as read.")
        case "clear":
            try store.clear()
            print("Cleared notifications.")
        default:
            let title = first
            let body = optionValue("--body", in: args) ?? ""
            let source = optionValue("--source", in: args) ?? "CLI"
            let id = optionValue("--id", in: args)
            let status = try parseStatus(optionValue("--status", in: args) ?? "review")
            let level = try parseOptionalLevel(optionValue("--level", in: args))
            let readAt = args.contains("--read") ? Date() : nil
            let item = try store.append(
                id: id,
                source: source,
                title: title,
                body: body,
                status: status,
                level: level,
                readAt: readAt
            )
            print(item.id)
        }
    }

    private func pet(_ args: [String]) throws {
        guard let command = args.first else {
            throw RightClickKitError.invalidValue(
                "usage: rck pet list|current|use <id|rck-dimo|fireball|default>|install <pet-folder>",
                URL(fileURLWithPath: ".")
            )
        }

        switch command {
        case "list":
            let current = currentPetID()
            let installed = try installedPetIDs().filter { builtInPetNames[$0] == nil }
            print("rck-dimo\t\(current == "rck-dimo" ? "current" : "available")\tRCK Dimo")
            print("fireball\t\(current == "fireball" ? "current" : "available")\tBuilt-in Fireball")
            for id in installed {
                print("\(id)\t\(current == id ? "current" : "available")\t\(petDisplayName(id: id) ?? id)")
            }
        case "current":
            print(currentPetID())
        case "use":
            guard let id = args.dropFirst().first else {
                throw RightClickKitError.invalidValue("usage: rck pet use <id|rck-dimo|fireball|default>", URL(fileURLWithPath: "."))
            }
            if id == "default" || id == defaultPetID {
                try? FileManager.default.removeItem(at: paths.currentPetURL)
                print("Current pet: \(defaultPetID)")
                return
            }
            if builtInPetNames[id] != nil {
                try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
                try "\(id)\n".write(to: paths.currentPetURL, atomically: true, encoding: .utf8)
                print("Current pet: \(id)")
                return
            }
            let folder = paths.petsDirectory.appendingPathComponent(id, isDirectory: true)
            guard isValidPetFolder(folder) else {
                throw RightClickKitError.invalidValue("pet not installed or missing spritesheet.webp: \(id)", folder)
            }
            try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true)
            try "\(id)\n".write(to: paths.currentPetURL, atomically: true, encoding: .utf8)
            print("Current pet: \(id)")
        case "install":
            guard let rawFolder = args.dropFirst().first else {
                throw RightClickKitError.invalidValue("usage: rck pet install <pet-folder>", URL(fileURLWithPath: "."))
            }
            let source = URL(fileURLWithPath: rawFolder).standardizedFileURL
            let id = try installPet(from: source)
            print("Installed pet: \(id)")
        default:
            throw RightClickKitError.invalidValue(
                "usage: rck pet list|current|use <id|rck-dimo|fireball|default>|install <pet-folder>",
                URL(fileURLWithPath: ".")
            )
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

    private func parseStatus(_ rawValue: String) throws -> ActivityStatus {
        guard let status = ActivityStatus(rawValue: rawValue) else {
            throw RightClickKitError.invalidValue(
                "unknown notification status: \(rawValue)",
                URL(fileURLWithPath: ".")
            )
        }
        return status
    }

    private func parseOptionalLevel(_ rawValue: String?) throws -> ActivityLevel? {
        guard let rawValue else {
            return nil
        }
        guard let level = ActivityLevel(rawValue: rawValue) else {
            throw RightClickKitError.invalidValue(
                "unknown notification level: \(rawValue)",
                URL(fileURLWithPath: ".")
            )
        }
        return level
    }

    private func currentPetID() -> String {
        let selected = (try? String(contentsOf: paths.currentPetURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return selected?.isEmpty == false ? selected! : defaultPetID
    }

    private func installedPetIDs() throws -> [String] {
        guard FileManager.default.fileExists(atPath: paths.petsDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: paths.petsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { isValidPetFolder($0) }
        .map(\.lastPathComponent)
        .sorted()
    }

    private func petDisplayName(id: String) -> String? {
        let manifestURL = paths.petsDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(RCKPetManifest.self, from: data)
        else {
            return nil
        }
        return manifest.displayName ?? manifest.name
    }

    private func installPet(from source: URL) throws -> String {
        guard isValidPetFolder(source) else {
            throw RightClickKitError.invalidValue("pet folder must contain pet.json and/or spritesheet.webp", source)
        }

        let manifest = readPetManifest(in: source)
        let id = sanitizePetID(manifest?.id ?? manifest?.name ?? source.lastPathComponent)
        guard !id.isEmpty else {
            throw RightClickKitError.invalidValue("pet id is empty", source)
        }

        let destination = paths.petsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: paths.petsDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let sourceSpritesheet = try petSpritesheetURL(in: source)
        try FileManager.default.copyItem(
            at: sourceSpritesheet,
            to: destination.appendingPathComponent("spritesheet.webp")
        )

        let sourceManifest = source.appendingPathComponent("pet.json")
        if FileManager.default.fileExists(atPath: sourceManifest.path) {
            try FileManager.default.copyItem(
                at: sourceManifest,
                to: destination.appendingPathComponent("pet.json")
            )
        } else {
            let manifest = RCKPetManifest(id: id, name: id, displayName: id, spritesheet: "spritesheet.webp")
            let data = try JSONEncoder.pretty.encode(manifest)
            try data.write(to: destination.appendingPathComponent("pet.json"), options: [.atomic])
        }
        return id
    }

    private func isValidPetFolder(_ folder: URL) -> Bool {
        (try? petSpritesheetURL(in: folder)) != nil
    }

    private func petSpritesheetURL(in folder: URL) throws -> URL {
        if let manifest = readPetManifest(in: folder),
           let rawPath = manifest.spritesheetPath
        {
            let url = rawPath.hasPrefix("/") ? URL(fileURLWithPath: rawPath) : folder.appendingPathComponent(rawPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let fallback = folder.appendingPathComponent("spritesheet.webp")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        throw RightClickKitError.invalidValue("missing spritesheet.webp", folder)
    }

    private func readPetManifest(in folder: URL) -> RCKPetManifest? {
        let url = folder.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RCKPetManifest.self, from: data)
    }

    private func sanitizePetID(_ rawValue: String) -> String {
        rawValue
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
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
          rck notify <title> [--body TEXT] [--level info|success|warning|danger] [--status running|waiting|review|failed|done] [--source NAME] [--id ID]
          rck notify list|read|clear
          rck pet list|current|use <id|rck-dimo|fireball|default>|install <pet-folder>
          rck config
        """)
    }
}

private struct RCKPetManifest: Codable {
    var id: String?
    var name: String?
    var displayName: String?
    var description: String?
    var spritesheet: String?
    var explicitSpritesheetPath: String?
    var spritesheetURL: String?
    var spritesheetUrl: String?

    init(
        id: String? = nil,
        name: String? = nil,
        displayName: String? = nil,
        description: String? = nil,
        spritesheet: String? = nil,
        explicitSpritesheetPath: String? = nil,
        spritesheetURL: String? = nil,
        spritesheetUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.spritesheet = spritesheet
        self.explicitSpritesheetPath = explicitSpritesheetPath
        self.spritesheetURL = spritesheetURL
        self.spritesheetUrl = spritesheetUrl
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case description
        case spritesheet
        case explicitSpritesheetPath = "spritesheetPath"
        case spritesheetURL
        case spritesheetUrl
    }

    var spritesheetPath: String? {
        spritesheet ?? explicitSpritesheetPath ?? spritesheetURL ?? spritesheetUrl
    }
}

exit(RCKCLI(arguments: CommandLine.arguments).run())
