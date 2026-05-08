import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let path: String
}

enum InstalledAppCatalog {
    static func load() -> [InstalledApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var appsByPath: [String: InstalledApp] = [:]
        for root in roots {
            scan(root: root, into: &appsByPath)
        }

        return appsByPath.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func scan(root: URL, into appsByPath: inout [String: InstalledApp]) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            if let app = loadApp(at: url) {
                appsByPath[url.path] = app
            }
            enumerator.skipDescendants()
        }
    }

    private static func loadApp(at url: URL) -> InstalledApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }

        let bundleIdentifier = info["CFBundleIdentifier"] as? String ?? ""
        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

        return InstalledApp(
            id: url.path,
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url.path
        )
    }
}
