import Darwin
import Foundation

public enum ActivityLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case info
    case success
    case warning
    case danger
}

public enum ActivityStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case running
    case waiting
    case review
    case failed
    case done

    public var isLoading: Bool {
        self == .running
    }

    public var defaultLevel: ActivityLevel {
        switch self {
        case .running:
            .info
        case .waiting:
            .warning
        case .review, .done:
            .success
        case .failed:
            .danger
        }
    }

    public func defaultExpiresAt(from date: Date = Date()) -> Date {
        switch self {
        case .running:
            date.addingTimeInterval(180)
        case .failed:
            date.addingTimeInterval(3_600)
        case .waiting:
            date.addingTimeInterval(86_400)
        case .review, .done:
            date.addingTimeInterval(604_800)
        }
    }
}

public enum ActivityMascotState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case waiting
    case review
    case failed
}

public struct ActivityItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var source: String
    public var title: String
    public var body: String
    public var status: ActivityStatus
    public var level: ActivityLevel
    public var isLoading: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    public var readAt: Date?
    public var actionID: String?

    public init(
        id: String = UUID().uuidString,
        source: String,
        title: String,
        body: String = "",
        status: ActivityStatus,
        level: ActivityLevel? = nil,
        isLoading: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil,
        readAt: Date? = nil,
        actionID: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.status = status
        self.level = level ?? status.defaultLevel
        self.isLoading = isLoading ?? status.isLoading
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt ?? status.defaultExpiresAt(from: updatedAt)
        self.readAt = readAt
        self.actionID = actionID
    }
}

public struct ActivitySummary: Codable, Equatable, Sendable {
    public var badgeCount: Int
    public var runningCount: Int
    public var waitingCount: Int
    public var reviewCount: Int
    public var failedCount: Int
    public var totalCount: Int
    public var mascotState: ActivityMascotState

    public init(
        badgeCount: Int,
        runningCount: Int,
        waitingCount: Int,
        reviewCount: Int,
        failedCount: Int,
        totalCount: Int,
        mascotState: ActivityMascotState
    ) {
        self.badgeCount = badgeCount
        self.runningCount = runningCount
        self.waitingCount = waitingCount
        self.reviewCount = reviewCount
        self.failedCount = failedCount
        self.totalCount = totalCount
        self.mascotState = mascotState
    }

    public static let empty = ActivitySummary(
        badgeCount: 0,
        runningCount: 0,
        waitingCount: 0,
        reviewCount: 0,
        failedCount: 0,
        totalCount: 0,
        mascotState: .idle
    )
}

public struct ActivityStore {
    public let paths: RCKPaths

    public init(paths: RCKPaths = RCKPaths()) {
        self.paths = paths
    }

    public func list(includeExpired: Bool = false, now: Date = Date()) throws -> [ActivityItem] {
        try withLock {
            let items = try loadItemsUnlocked()
            let filtered = includeExpired ? items : activeItems(from: items, now: now)
            return sorted(filtered)
        }
    }

    @discardableResult
    public func append(
        id: String? = nil,
        source: String,
        title: String,
        body: String = "",
        status: ActivityStatus,
        level: ActivityLevel? = nil,
        isLoading: Bool? = nil,
        expiresAt: Date? = nil,
        readAt: Date? = nil,
        actionID: String? = nil
    ) throws -> ActivityItem {
        try mutate { items in
            let now = Date()
            let item = ActivityItem(
                id: id ?? UUID().uuidString,
                source: source,
                title: title,
                body: body,
                status: status,
                level: level,
                isLoading: isLoading,
                createdAt: now,
                updatedAt: now,
                expiresAt: expiresAt,
                readAt: readAt,
                actionID: actionID
            )
            items.removeAll { $0.id == item.id }
            items.append(item)
            return item
        }
    }

    @discardableResult
    public func startRun(serviceID: String, title: String, items: [String]) throws -> ActivityItem {
        let body = items.isEmpty ? "Running from Finder context" : itemSummary(items)
        return try append(
            source: "RightClickKit",
            title: title,
            body: body,
            status: .running,
            actionID: serviceID
        )
    }

    @discardableResult
    public func finishRun(
        id: String?,
        serviceID: String,
        title: String,
        status: ActivityStatus,
        body: String,
        level: ActivityLevel? = nil
    ) throws -> ActivityItem {
        try mutate { items in
            let now = Date()
            if let id, let index = items.firstIndex(where: { $0.id == id }) {
                items[index].title = title
                items[index].body = body
                items[index].status = status
                items[index].level = level ?? status.defaultLevel
                items[index].isLoading = status.isLoading
                items[index].updatedAt = now
                items[index].expiresAt = status.defaultExpiresAt(from: now)
                items[index].readAt = nil
                items[index].actionID = serviceID
                return items[index]
            }

            let item = ActivityItem(
                source: "RightClickKit",
                title: title,
                body: body,
                status: status,
                level: level,
                actionID: serviceID
            )
            items.append(item)
            return item
        }
    }

    public func markAllRead() throws {
        try mutate { items in
            let now = Date()
            for index in items.indices {
                items[index].readAt = now
                items[index].updatedAt = now
            }
        }
    }

    public func markRead(id: String) throws {
        try mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return
            }
            items[index].readAt = Date()
            items[index].updatedAt = Date()
        }
    }

    public func clear() throws {
        try mutate { items in
            items.removeAll()
        }
    }

    public func summary(now: Date = Date()) throws -> ActivitySummary {
        let items = try list(now: now)
        return Self.summary(for: items)
    }

    public static func summary(for items: [ActivityItem]) -> ActivitySummary {
        let runningCount = items.filter { $0.status == .running }.count
        let unread = items.filter { $0.readAt == nil }
        let failedCount = unread.filter { $0.status == .failed }.count
        let waitingCount = unread.filter { $0.status == .waiting }.count
        let reviewCount = unread.filter { $0.status == .review || $0.status == .done }.count
        let badgeCount = min(99, runningCount + failedCount + waitingCount + reviewCount)

        let mascotState: ActivityMascotState
        if runningCount > 0 {
            mascotState = .running
        } else if failedCount > 0 {
            mascotState = .failed
        } else if waitingCount > 0 {
            mascotState = .waiting
        } else if reviewCount > 0 {
            mascotState = .review
        } else {
            mascotState = .idle
        }

        return ActivitySummary(
            badgeCount: badgeCount,
            runningCount: runningCount,
            waitingCount: waitingCount,
            reviewCount: reviewCount,
            failedCount: failedCount,
            totalCount: items.count,
            mascotState: mascotState
        )
    }

    private func mutate<T>(_ body: (inout [ActivityItem]) throws -> T) throws -> T {
        try withLock {
            var items = activeItems(from: try loadItemsUnlocked())
            let result = try body(&items)
            try saveItemsUnlocked(trimmed(sorted(items)))
            return result
        }
    }

    private func loadItemsUnlocked() throws -> [ActivityItem] {
        guard FileManager.default.fileExists(atPath: paths.activityURL.path) else {
            return []
        }

        let data = try Data(contentsOf: paths.activityURL)
        guard !data.isEmpty else {
            return []
        }

        return try Self.decoder.decode([ActivityItem].self, from: data)
    }

    private func saveItemsUnlocked(_ items: [ActivityItem]) throws {
        try FileManager.default.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(items)
        try data.write(to: paths.activityURL, options: [.atomic])
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )

        let fd = open(paths.activityLockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            let message = String(cString: strerror(errno))
            throw RightClickKitError.invalidValue("could not open activity lock: \(message)", paths.activityLockURL)
        }
        defer { close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            let message = String(cString: strerror(errno))
            throw RightClickKitError.invalidValue("could not lock activity store: \(message)", paths.activityLockURL)
        }
        defer { flock(fd, LOCK_UN) }

        return try body()
    }

    private func activeItems(from items: [ActivityItem], now: Date = Date()) -> [ActivityItem] {
        items.filter { item in
            guard let expiresAt = item.expiresAt else {
                return true
            }
            return expiresAt > now
        }
    }

    private func sorted(_ items: [ActivityItem]) -> [ActivityItem] {
        items.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    private func trimmed(_ items: [ActivityItem]) -> [ActivityItem] {
        Array(items.prefix(200))
    }

    private func itemSummary(_ items: [String]) -> String {
        if items.count == 1 {
            return items[0]
        }
        return "\(items.count) selected items"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder.pretty
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
