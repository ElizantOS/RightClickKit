import Foundation

public enum ServiceStatus: String, Codable, Equatable {
    case installed
    case notInstalled
    case modified
    case error

    public var title: String {
        switch self {
        case .installed: "Installed"
        case .notInstalled: "Not Installed"
        case .modified: "Modified"
        case .error: "Error"
        }
    }
}
