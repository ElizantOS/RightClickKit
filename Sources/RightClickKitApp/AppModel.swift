import AppKit
import Foundation
import RightClickKitCore

@MainActor
final class AppModel: ObservableObject {
    @Published var actions: [EditableAction] = []
    @Published var installedApps: [InstalledApp] = []
    @Published var status = "Ready"

    private let paths = RCKPaths()

    func reload() {
        do {
            let config = try currentConfig()
            let loaded = try ServiceStore(servicesDirectory: config.servicesURL).loadServices()
            actions = try loaded.map { service in
                let script = try String(contentsOf: service.scriptURL, encoding: .utf8)
                let editable = EditableAction(definition: service, scriptText: script)
                editable.status = status(for: service)
                loadLog(for: editable)
                return editable
            }
            status = "Loaded \(actions.count) action(s) from \(config.servicesURL.path)."
        } catch {
            status = "\(error)"
        }
    }

    func reloadInstalledApps() {
        installedApps = InstalledAppCatalog.load()
    }

    func save(_ action: EditableAction) {
        do {
            try action.yamlText.write(to: action.directory.appendingPathComponent("service.yaml"), atomically: true, encoding: .utf8)
            try action.scriptText.write(to: action.directory.appendingPathComponent(action.scriptName), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: action.directory.appendingPathComponent(action.scriptName).path)
            status = "Saved \(action.title)."
            reload()
        } catch {
            status = "\(error)"
        }
    }

    func install() {
        do {
            let config = try currentConfig()
            try ensureRCKAvailable(for: config)
            try ConfigStore(paths: paths).save(config)
            let loaded = try ServiceStore(servicesDirectory: config.servicesURL).loadServices()
            let installed = try WorkflowInstaller(paths: paths).install(services: loaded, rckPath: config.rckPath)
            status = "Installed \(installed.count) workflow(s)."
            reload()
        } catch {
            status = "\(error)"
        }
    }

    func saveAndInstall(_ action: EditableAction) {
        save(action)
        install()
    }

    func test(_ action: EditableAction) {
        do {
            save(action)
            let config = try currentConfig()
            let status = try ServiceRunner(config: config, paths: paths).run(serviceID: action.id, arguments: [])
            loadLog(for: action)
            self.status = "Test finished with exit \(status)."
        } catch {
            status = "\(error)"
        }
    }

    func uninstall() {
        do {
            let removed = try WorkflowInstaller(paths: paths).uninstallManagedWorkflows()
            status = "Removed \(removed.count) workflow(s)."
            reload()
        } catch {
            status = "\(error)"
        }
    }

    func repairHelper() {
        do {
            try ensureRCKAvailable(for: try currentConfig())
            status = "Helper repaired."
        } catch {
            status = "\(error)"
        }
    }

    func openLogs() {
        NSWorkspace.shared.open(paths.logDirectory)
    }

    func loadLog(for action: EditableAction) {
        let serviceURL = paths.logURL(serviceID: action.id)
        let launcherURL = paths.launcherLogURL(serviceID: action.id)
        var sections: [String] = []

        if let text = try? String(contentsOf: serviceURL, encoding: .utf8) {
            sections.append("== service log ==\n" + String(text.suffix(12000)))
        }
        if let text = try? String(contentsOf: launcherURL, encoding: .utf8) {
            sections.append("== launcher log ==\n" + String(text.suffix(12000)))
        }

        action.logText = sections.joined(separator: "\n\n")
    }

    private func status(for service: ServiceDefinition) -> ServiceStatus {
        let workflowURL = paths.workflowURL(title: service.title)
        guard FileManager.default.fileExists(atPath: workflowURL.path) else {
            return .notInstalled
        }
        return WorkflowInstaller(paths: paths).isManagedWorkflow(workflowURL) ? .installed : .error
    }

    private func currentConfig() throws -> RightClickKitConfig {
        if let repositoryRoot = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_REPOSITORY_ROOT"],
           FileManager.default.fileExists(atPath: URL(fileURLWithPath: repositoryRoot).appendingPathComponent("services").path) {
            return RightClickKitConfig(repositoryRoot: repositoryRoot, rckPath: defaultRCKPath())
        }

        if let repositoryRoot = bundledRepositoryRoot() {
            return RightClickKitConfig(repositoryRoot: repositoryRoot.path, rckPath: defaultRCKPath())
        }

        if FileManager.default.fileExists(atPath: paths.configURL.path),
           let config = try? ConfigStore(paths: paths).load(),
           FileManager.default.fileExists(atPath: config.servicesURL.path) {
            return config
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return RightClickKitConfig(repositoryRoot: currentDirectory.path, rckPath: defaultRCKPath())
    }

    private func defaultRCKPath() -> String {
        paths.binDirectory.appendingPathComponent("rck").path
    }

    private func ensureRCKAvailable(for config: RightClickKitConfig) throws {
        let rckURL = URL(fileURLWithPath: config.rckPath)
        if FileManager.default.isExecutableFile(atPath: rckURL.path) {
            return
        }

        guard let bundledRCK = bundledRCKURL(),
              FileManager.default.isExecutableFile(atPath: bundledRCK.path)
        else {
            throw RightClickKitError.invalidValue("Missing rck executable at \(config.rckPath)", URL(fileURLWithPath: config.repositoryRoot))
        }

        try FileManager.default.createDirectory(at: rckURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: rckURL.path) {
            try FileManager.default.removeItem(at: rckURL)
        }
        try FileManager.default.copyItem(at: bundledRCK, to: rckURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rckURL.path)
    }

    private func bundledRepositoryRoot() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("repository-root.txt"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/repository-root.txt")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let text = try? String(contentsOf: candidate, encoding: .utf8) else {
                continue
            }
            let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("services").path) {
                return url
            }
        }
        return nil
    }

    private func bundledRCKURL() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("rck"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/rck")
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
