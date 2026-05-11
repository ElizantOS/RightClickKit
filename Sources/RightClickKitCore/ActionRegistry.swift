import Foundation

public enum ActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case builtIn
    case script
    case nativeTool
    case agent
    case workflow

    public var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .script: "Script"
        case .nativeTool: "Native Tool"
        case .agent: "AI Agent"
        case .workflow: "Workflow"
        }
    }
}

public enum NativeToolID: String, Codable, CaseIterable, Equatable, Sendable {
    case directoryTree = "directory-tree"
    case storageAnalysis = "storage-analysis"

    public var title: String {
        switch self {
        case .directoryTree: "Directory Tree"
        case .storageAnalysis: "Storage Analysis"
        }
    }
}

public indirect enum ActionEntryPoint: Codable, Equatable, Sendable {
    case builtIn(ActionType)
    case script(command: String)
    case nativeTool(NativeToolID)
    case agent(command: String, prompt: String)
    case workflow([ActionEntryPoint])

    public var kind: ActionKind {
        switch self {
        case .builtIn: .builtIn
        case .script: .script
        case .nativeTool: .nativeTool
        case .agent: .agent
        case .workflow: .workflow
        }
    }
}

public struct ActionManifest: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var kind: ActionKind
    public var accepts: [ServiceAccepts]
    public var entryPoint: ActionEntryPoint
    public var systemImage: String
    public var isDestructive: Bool
    public var requiresConfirmation: Bool

    public init(
        id: String,
        title: String,
        description: String,
        kind: ActionKind,
        accepts: [ServiceAccepts],
        entryPoint: ActionEntryPoint,
        systemImage: String,
        isDestructive: Bool = false,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.accepts = accepts
        self.entryPoint = entryPoint
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct ActionRegistry: Sendable {
    public let manifests: [ActionManifest]

    public init(manifests: [ActionManifest] = Self.builtInManifests) {
        self.manifests = manifests
    }

    public func manifest(for type: ActionType) -> ActionManifest {
        manifests.first { $0.id == type.manifestID } ?? manifests.first { manifest in
            if case let .builtIn(candidate) = manifest.entryPoint {
                return candidate == type
            }
            return false
        } ?? type.fallbackManifest
    }

    public func manifest(id: String) -> ActionManifest? {
        manifests.first { $0.id == id }
    }

    public static let builtIn = ActionRegistry()

    public static let builtInManifests: [ActionManifest] = [
        ActionManifest(
            id: "open-with-app",
            title: "Open with App",
            description: "Open selected files or folders with a chosen macOS app.",
            kind: .builtIn,
            accepts: [.file, .folder],
            entryPoint: .builtIn(.openWithApp),
            systemImage: "app"
        ),
        ActionManifest(
            id: "open-with-code-editor",
            title: "Open with Code Editor",
            description: "Open selected files or folders in a code-compatible editor.",
            kind: .builtIn,
            accepts: [.file, .folder],
            entryPoint: .builtIn(.openWithCodeEditor),
            systemImage: "curlybraces"
        ),
        ActionManifest(
            id: "open-terminal-here",
            title: "Open Terminal Here",
            description: "Open a terminal at the selected folder or file location.",
            kind: .builtIn,
            accepts: [.file, .folder],
            entryPoint: .builtIn(.openTerminalHere),
            systemImage: "terminal"
        ),
        ActionManifest(
            id: "copy-paths",
            title: "Copy Paths",
            description: "Copy Finder-selected paths in a chosen format.",
            kind: .builtIn,
            accepts: [.file, .folder],
            entryPoint: .builtIn(.copyPaths),
            systemImage: "doc.on.doc"
        ),
        ActionManifest(
            id: "run-command",
            title: "Run Command",
            description: "Run a shell command with Finder-selected paths.",
            kind: .script,
            accepts: [.file, .folder],
            entryPoint: .builtIn(.runCommand),
            systemImage: "play.rectangle"
        ),
        ActionManifest(
            id: "show-directory-tree",
            title: "Show Directory Tree",
            description: "Open a native directory tree viewer for selected files or folders.",
            kind: .nativeTool,
            accepts: [.file, .folder],
            entryPoint: .nativeTool(.directoryTree),
            systemImage: "list.bullet.indent"
        ),
        ActionManifest(
            id: "analyze-storage",
            title: "Analyze Storage",
            description: "Open a native storage analysis viewer for selected files or folders.",
            kind: .nativeTool,
            accepts: [.file, .folder],
            entryPoint: .nativeTool(.storageAnalysis),
            systemImage: "chart.pie"
        )
    ]
}

private extension ActionType {
    var manifestID: String {
        switch self {
        case .openWithApp: "open-with-app"
        case .openWithCodeEditor: "open-with-code-editor"
        case .openTerminalHere: "open-terminal-here"
        case .copyPaths: "copy-paths"
        case .runCommand: "run-command"
        case .showDirectoryTree: "show-directory-tree"
        case .analyzeStorage: "analyze-storage"
        }
    }

    var fallbackManifest: ActionManifest {
        ActionManifest(
            id: rawValue,
            title: rawValue,
            description: "",
            kind: .builtIn,
            accepts: [.file, .folder],
            entryPoint: .builtIn(self),
            systemImage: "gearshape"
        )
    }
}
