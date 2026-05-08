import Foundation
import RightClickKitCore
import SwiftUI

@MainActor
final class EditableAction: ObservableObject, Identifiable {
    let id: String
    let directory: URL
    let scriptName: String
    private let originalShell: String
    private let originalConfirm: Bool

    @Published var title: String { didSet { markModified() } }
    @Published var description: String { didSet { markModified() } }
    @Published var enabled: Bool { didSet { markModified() } }
    @Published var acceptsFile: Bool { didSet { markModified() } }
    @Published var acceptsFolder: Bool { didSet { markModified() } }
    @Published var mode: ServiceMode { didSet { markModified() } }
    @Published var action: ActionConfig { didSet { markModified() } }
    @Published var rawScript: String { didSet { markModified() } }
    @Published var logText: String = ""
    @Published var status: ServiceStatus = .notInstalled

    init(definition: ServiceDefinition, scriptText: String) {
        self.id = definition.id
        self.directory = definition.directory
        self.scriptName = definition.script
        self.originalShell = definition.shell
        self.originalConfirm = definition.confirm
        self.title = definition.title
        self.description = definition.description
        self.enabled = definition.enabled
        self.acceptsFile = definition.accepts.contains(.file)
        self.acceptsFolder = definition.accepts.contains(.folder)
        self.mode = definition.mode
        self.action = definition.action ?? ActionConfig()
        self.rawScript = scriptText
    }

    var isRawScript: Bool {
        get { mode == .rawScript }
        set { mode = newValue ? .rawScript : .action }
    }

    var scriptText: String {
        mode == .action ? ActionScriptGenerator.generate(action) : rawScript
    }

    var serviceDefinition: ServiceDefinition {
        let accepts = acceptsValues
        return ServiceDefinition(
            id: id,
            title: title,
            description: description,
            accepts: accepts.isEmpty ? [.file, .folder] : accepts,
            shell: originalShell,
            script: scriptName,
            enabled: enabled,
            confirm: originalConfirm,
            mode: mode,
            action: mode == .action ? action : nil,
            directory: directory
        )
    }

    var yamlText: String {
        YAMLServiceCodec.dump(serviceDefinition)
    }

    var actionTypeBinding: Binding<ActionType> {
        Binding(
            get: { self.action.type },
            set: { self.action.type = $0 }
        )
    }

    var pathFormatBinding: Binding<CopyPathsFormat> {
        Binding(
            get: { self.action.pathFormat },
            set: { self.action.pathFormat = $0 }
        )
    }

    private var acceptsValues: [ServiceAccepts] {
        var values: [ServiceAccepts] = []
        if acceptsFile { values.append(.file) }
        if acceptsFolder { values.append(.folder) }
        return values
    }

    private func markModified() {
        if status != .modified {
            status = .modified
        }
    }
}
