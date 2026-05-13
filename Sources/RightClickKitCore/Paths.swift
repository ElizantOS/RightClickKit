import Foundation

public struct RCKPaths {
    public let home: URL

    public init(home: URL? = nil) {
        if let home {
            self.home = home
        } else if let override = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_HOME"], !override.isEmpty {
            self.home = URL(fileURLWithPath: override)
        } else {
            self.home = FileManager.default.homeDirectoryForCurrentUser
        }
    }

    public var supportDirectory: URL {
        home.appendingPathComponent(".rightclickkit", isDirectory: true)
    }

    public var binDirectory: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    public var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    public var activityURL: URL {
        supportDirectory.appendingPathComponent("activity.json")
    }

    public var activityLockURL: URL {
        supportDirectory.appendingPathComponent("activity.lock")
    }

    public var petsDirectory: URL {
        supportDirectory.appendingPathComponent("pets", isDirectory: true)
    }

    public var currentPetURL: URL {
        supportDirectory.appendingPathComponent("current-pet.txt")
    }

    public var userServicesDirectory: URL {
        home.appendingPathComponent("Library/Services", isDirectory: true)
    }

    public var logDirectory: URL {
        home.appendingPathComponent("Library/Logs/RightClickKit", isDirectory: true)
    }

    public func workflowURL(title: String) -> URL {
        userServicesDirectory.appendingPathComponent("\(title).workflow", isDirectory: true)
    }

    public func logURL(serviceID: String) -> URL {
        logDirectory.appendingPathComponent("\(serviceID).log")
    }

    public func launcherLogURL(serviceID: String) -> URL {
        logDirectory.appendingPathComponent("\(serviceID).launcher.log")
    }
}
