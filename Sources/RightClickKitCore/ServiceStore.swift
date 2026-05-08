import Foundation

public struct ServiceStore {
    public let servicesDirectory: URL
    public let fileManager: FileManager

    public init(servicesDirectory: URL, fileManager: FileManager = .default) {
        self.servicesDirectory = servicesDirectory
        self.fileManager = fileManager
    }

    public func loadServices() throws -> [ServiceDefinition] {
        guard fileManager.fileExists(atPath: servicesDirectory.path) else {
            return []
        }

        let children = try fileManager.contentsOfDirectory(
            at: servicesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try children.compactMap { directory in
            let yamlURL = directory.appendingPathComponent("service.yaml")
            guard fileManager.fileExists(atPath: yamlURL.path) else {
                return nil
            }
            return try YAMLServiceCodec.load(from: yamlURL)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func loadService(id: String) throws -> ServiceDefinition {
        let services = try loadServices()
        guard let service = services.first(where: { $0.id == id }) else {
            throw RightClickKitError.serviceNotFound(id)
        }
        return service
    }

    public func save(_ service: ServiceDefinition, scriptText: String? = nil) throws {
        try fileManager.createDirectory(at: service.directory, withIntermediateDirectories: true)
        try YAMLServiceCodec.dump(service).write(to: service.yamlURL, atomically: true, encoding: .utf8)

        let text = scriptText ?? service.generatedOrExistingScriptText(fileManager: fileManager)
        try text.write(to: service.scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: service.scriptURL.path)
    }

    public func materializeActionScripts(for services: [ServiceDefinition]) throws {
        for service in services where service.mode == .action {
            try save(service, scriptText: service.generatedScriptText)
        }
    }
}

public extension ServiceDefinition {
    var generatedScriptText: String {
        ActionScriptGenerator.generate(action ?? ActionConfig())
    }

    func generatedOrExistingScriptText(fileManager: FileManager = .default) -> String {
        if mode == .action {
            return generatedScriptText
        }

        return (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? """
        #!/bin/zsh
        # Raw Script mode. Finder-selected paths are available as "$@".
        printf '%s\\n' "$@"
        """
    }
}
