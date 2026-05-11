import Foundation

public enum RightClickKitError: Error, CustomStringConvertible {
    case missingField(String, URL)
    case invalidValue(String, URL)
    case serviceNotFound(String)
    case unmanagedWorkflowExists(URL)
    case commandFailed(String, Int32)

    public var description: String {
        switch self {
        case let .missingField(field, url):
            "Missing required field '\(field)' in \(url.path)"
        case let .invalidValue(message, url):
            "Invalid value in \(url.path): \(message)"
        case let .serviceNotFound(id):
            "Service not found: \(id)"
        case let .unmanagedWorkflowExists(url):
            "Refusing to overwrite unmanaged workflow at \(url.path)"
        case let .commandFailed(command, status):
            "Command failed with exit status \(status): \(command)"
        }
    }
}

public enum ServiceAccepts: String, Codable, CaseIterable, Sendable {
    case file
    case folder
}

public enum ServiceMode: String, Codable, Equatable, Sendable {
    case action
    case rawScript
}

public enum ActionType: String, Codable, CaseIterable, Equatable, Sendable {
    case openWithApp
    case openWithCodeEditor
    case openTerminalHere
    case copyPaths
    case runCommand
    case showDirectoryTree
    case analyzeStorage

    public var title: String {
        ActionRegistry.builtIn.manifest(for: self).title
    }

    public var systemImage: String {
        ActionRegistry.builtIn.manifest(for: self).systemImage
    }

    public var kind: ActionKind {
        ActionRegistry.builtIn.manifest(for: self).kind
    }
}

public enum CopyPathsFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case lines
    case spaces
    case json

    public var title: String {
        switch self {
        case .lines: "Lines"
        case .spaces: "Spaces"
        case .json: "JSON"
        }
    }
}

public struct ActionConfig: Codable, Equatable, Sendable {
    public var type: ActionType
    public var appName: String
    public var bundleID: String
    public var codeCommand: String
    public var terminalApp: String
    public var command: String
    public var pathFormat: CopyPathsFormat

    public init(
        type: ActionType = .openWithApp,
        appName: String = "Cursor",
        bundleID: String = "",
        codeCommand: String = "/usr/local/bin/code",
        terminalApp: String = "Terminal",
        command: String = "pwd && ls -la",
        pathFormat: CopyPathsFormat = .lines
    ) {
        self.type = type
        self.appName = appName
        self.bundleID = bundleID
        self.codeCommand = codeCommand
        self.terminalApp = terminalApp
        self.command = command
        self.pathFormat = pathFormat
    }
}

public struct ServiceDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var accepts: [ServiceAccepts]
    public var shell: String
    public var script: String
    public var enabled: Bool
    public var confirm: Bool
    public var mode: ServiceMode
    public var action: ActionConfig?
    public var directory: URL

    public init(
        id: String,
        title: String,
        description: String,
        accepts: [ServiceAccepts],
        shell: String,
        script: String,
        enabled: Bool,
        confirm: Bool,
        mode: ServiceMode = .rawScript,
        action: ActionConfig? = nil,
        directory: URL
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.accepts = accepts
        self.shell = shell
        self.script = script
        self.enabled = enabled
        self.confirm = confirm
        self.mode = mode
        self.action = action
        self.directory = directory
    }

    public var yamlURL: URL {
        directory.appendingPathComponent("service.yaml")
    }

    public var scriptURL: URL {
        directory.appendingPathComponent(script)
    }
}

public struct RightClickKitConfig: Codable, Equatable, Sendable {
    public var repositoryRoot: String
    public var rckPath: String

    public init(repositoryRoot: String, rckPath: String) {
        self.repositoryRoot = repositoryRoot
        self.rckPath = rckPath
    }

    public var repositoryURL: URL {
        URL(fileURLWithPath: repositoryRoot)
    }

    public var servicesURL: URL {
        repositoryURL.appendingPathComponent("services")
    }
}
