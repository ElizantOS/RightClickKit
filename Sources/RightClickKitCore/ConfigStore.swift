import Foundation

public struct ConfigStore {
    public let paths: RCKPaths

    public init(paths: RCKPaths = RCKPaths()) {
        self.paths = paths
    }

    public func load() throws -> RightClickKitConfig {
        let data = try Data(contentsOf: paths.configURL)
        return try JSONDecoder().decode(RightClickKitConfig.self, from: data)
    }

    public func save(_ config: RightClickKitConfig) throws {
        try FileManager.default.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: paths.configURL, options: [.atomic])
    }
}

public extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
