import Foundation
import RightClickKitCore

@MainActor
final class MacNotificationBridge {
    private let enabledKey = "RightClickKitAgent.macNotificationBridgeEnabled"
    private let dingTalkBundleIDs = ["5ZSL2CJU2T.com.dingtalk.mac"]
    private var timer: Timer?
    private var seenRecordIDs = Set<String>()
    private var isPolling = false
    private var postedPermissionWarning = false
    private var lastBridgeLogMessage = ""
    private var lastSnapshotSignature = ""

    func start() {
        guard isEnabled else { return }
        poll(seedOnly: true)
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll(seedOnly: false)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    private func poll(seedOnly: Bool) {
        guard !isPolling else { return }
        isPolling = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.readDingTalkNotifications()
            DispatchQueue.main.async {
                self.consume(result: result, seedOnly: seedOnly)
                self.isPolling = false
            }
        }
    }

    private func consume(result: BridgeReadResult, seedOnly: Bool) {
        switch result {
        case let .records(snapshot):
            postedPermissionWarning = false
            logSnapshotIfChanged(snapshot)
            var didPost = false
            for record in snapshot.records {
                if seenRecordIDs.contains(record.id) {
                    continue
                }
                seenRecordIDs.insert(record.id)
                guard !seedOnly else { continue }
                post(record)
                didPost = true
            }
            if didPost {
                AgentActions.notifyActivityChanged()
            }
        case .permissionDenied:
            appendBridgeLogOnce("notification database permission denied")
            postPermissionWarning()
        case .notFound:
            appendBridgeLogOnce("notification database not found")
            break
        }
    }

    private func post(_ record: MacNotificationRecord) {
        _ = try? ActivityStore().append(
            id: "macos-notification:\(record.id)",
            source: "DingTalk",
            title: record.title,
            body: record.body,
            status: .waiting,
            level: .warning,
            actionID: "macos-notification-bridge"
        )
    }

    private func postPermissionWarning() {
        guard !postedPermissionWarning else { return }
        postedPermissionWarning = true
        let agentPath = AgentPaths.agentAppURL.path
        let mainPath = AgentPaths.mainAppURL.path
        _ = try? ActivityStore().append(
            id: "macos-notification-bridge:full-disk-access",
            source: "RightClickKit",
            title: "Enable macOS notification bridge",
            body: "Grant Full Disk Access to the helper that reads notifications: \(agentPath). If it still fails after reinstalling, remove the old RightClickKit entries and add \(mainPath) plus the Agent again.",
            status: .waiting,
            level: .warning,
            actionID: "macos-notification-bridge"
        )
        AgentActions.notifyActivityChanged()
    }

    private func logSnapshotIfChanged(_ snapshot: BridgeReadSnapshot) {
        let signature = [
            "paths=\(snapshot.candidatePaths.joined(separator: "|"))",
            "ids=\(snapshot.matchedAppIdentifiers.joined(separator: "|"))",
            "rows=\(snapshot.matchedRowCount)",
            "records=\(snapshot.records.count)"
        ].joined(separator: ";")
        guard signature != lastSnapshotSignature else { return }
        lastSnapshotSignature = signature

        appendBridgeLog("found \(snapshot.candidatePaths.count) notification database candidate(s)")
        if snapshot.matchedAppIdentifiers.isEmpty {
            appendBridgeLog("no DingTalk app identifier found yet")
        } else {
            appendBridgeLog("DingTalk app identifier(s): \(snapshot.matchedAppIdentifiers.joined(separator: ", "))")
        }
        appendBridgeLog("read \(snapshot.records.count) DingTalk notification record(s) from \(snapshot.matchedRowCount) matching row(s)")
    }

    private nonisolated func readDingTalkNotifications() -> BridgeReadResult {
        let dbResult = notificationDatabaseURLs()
        switch dbResult {
        case let .success(urls):
            guard !urls.isEmpty else { return .notFound }
            var records: [MacNotificationRecord] = []
            var matchedIdentifiers = Set<String>()
            var matchedRowCount = 0
            for url in urls {
                let result = readRecords(from: url)
                records.append(contentsOf: result.records)
                matchedIdentifiers.formUnion(result.matchedAppIdentifiers)
                matchedRowCount += result.matchedRowCount
            }
            let snapshot = BridgeReadSnapshot(
                candidatePaths: urls.map(\.path).sorted(),
                matchedAppIdentifiers: Array(matchedIdentifiers).sorted(),
                matchedRowCount: matchedRowCount,
                records: records.sorted { $0.sortKey > $1.sortKey }
            )
            return .records(snapshot)
        case .permissionDenied:
            return .permissionDenied
        }
    }

    private nonisolated func appendBridgeLog(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RightClickKit", isDirectory: true)
            .appendingPathComponent("agent.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "[\(Date())] notification bridge: \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func appendBridgeLogOnce(_ message: String) {
        guard message != lastBridgeLogMessage else { return }
        lastBridgeLogMessage = message
        appendBridgeLog(message)
    }

    private nonisolated func notificationDatabaseURLs() -> DatabaseDiscoveryResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted"),
            home.appendingPathComponent("Library/Group Containers/group.com.apple.UserNotifications/Library/UserNotifications"),
            home.appendingPathComponent("Library/Application Support/NotificationCenter")
        ] + darwinUserNotificationRoots()

        var urls = Set<URL>()
        var sawPermissionDenied = false
        for root in roots {
            for candidate in directDatabaseCandidates(under: root) where FileManager.default.fileExists(atPath: candidate.path) {
                urls.insert(candidate)
            }

            let result = ProcessRunnerResult.run(
                "/usr/bin/find",
                arguments: [root.path, "-maxdepth", "6", "-type", "f", "-name", "db"]
            )
            if result.status != 0, result.output.contains("Operation not permitted") {
                sawPermissionDenied = true
                continue
            }
            result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
                .forEach { urls.insert($0) }
        }

        if sawPermissionDenied, urls.isEmpty {
            return .permissionDenied
        }
        return .success(Array(urls))
    }

    private nonisolated func darwinUserNotificationRoots() -> [URL] {
        let result = ProcessRunnerResult.run("/usr/bin/getconf", arguments: ["DARWIN_USER_DIR"])
        guard result.status == 0 else { return [] }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return [] }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        return [
            root.appendingPathComponent("com.apple.notificationcenter", isDirectory: true),
            root.appendingPathComponent("com.apple.notificationcenter/db2", isDirectory: true),
            root.appendingPathComponent("com.apple.notificationcenter/db", isDirectory: true)
        ]
    }

    private nonisolated func directDatabaseCandidates(under root: URL) -> [URL] {
        [
            root,
            root.appendingPathComponent("db"),
            root.appendingPathComponent("db/db"),
            root.appendingPathComponent("db2/db")
        ].filter { $0.lastPathComponent == "db" }
    }

    private nonisolated func readRecords(from dbURL: URL) -> DatabaseReadResult {
        let tables = sqliteLines(dbURL: dbURL, sql: "SELECT name FROM sqlite_master WHERE type='table';")
        guard tables.contains("record"), tables.contains("app") else {
            return .empty
        }

        let appColumns = tableColumns(dbURL: dbURL, table: "app")
        let recordColumns = tableColumns(dbURL: dbURL, table: "record")

        guard let appIdentifierColumn = firstExisting(["identifier", "bundle_id", "bundleid"], in: appColumns),
              let recordDataColumn = firstExisting(["data", "request", "notification", "payload"], in: recordColumns)
        else {
            return .empty
        }

        let appKeyColumn = firstExisting(["app_id", "id"], in: appColumns) ?? "ROWID"
        guard let recordAppColumn = firstExisting([appKeyColumn, "app_id", "app"], in: recordColumns) else {
            return .empty
        }
        let dateColumn = firstExisting(["delivered_date", "request_date", "date", "timestamp"], in: recordColumns)
        let dateExpression = dateColumn.map { "record.\(quoteIdentifier($0))" } ?? "0"
        let identifierExpression = "app.\(quoteIdentifier(appIdentifierColumn))"
        let dingTalkFilter = dingTalkIdentifierFilterSQL(identifierExpression: identifierExpression)
        let matchedIdentifiers = sqliteLines(
            dbURL: dbURL,
            sql: """
            SELECT DISTINCT \(identifierExpression)
            FROM app
            WHERE \(dingTalkFilter)
            ORDER BY \(identifierExpression)
            LIMIT 20;
            """
        )

        let sql = """
        SELECT record.ROWID, \(identifierExpression), \(dateExpression), hex(record.\(quoteIdentifier(recordDataColumn)))
        FROM record
        JOIN app ON record.\(quoteIdentifier(recordAppColumn)) = app.\(quoteIdentifier(appKeyColumn))
        WHERE \(dingTalkFilter)
        ORDER BY record.ROWID DESC
        LIMIT 80;
        """

        let lines = sqliteLines(dbURL: dbURL, sql: sql)
        let records: [MacNotificationRecord] = lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return nil }
            let rawID = "\(dbURL.path)#\(parts[0])"
            let sortKey = Double(parts[2]) ?? Double(parts[0]) ?? 0
            let strings = extractStrings(fromHex: parts[3])
            let message = bestMessage(from: strings, excluding: dingTalkBundleIDs + [parts[1]])
            guard !message.title.isEmpty || !message.body.isEmpty else { return nil }
            return MacNotificationRecord(
                id: rawID,
                title: message.title.isEmpty ? "DingTalk" : message.title,
                body: message.body,
                sortKey: sortKey
            )
        }
        return DatabaseReadResult(
            records: records,
            matchedAppIdentifiers: matchedIdentifiers,
            matchedRowCount: lines.count
        )
    }

    private nonisolated func tableColumns(dbURL: URL, table: String) -> Set<String> {
        Set(sqliteLines(dbURL: dbURL, sql: "PRAGMA table_info(\(quoteIdentifier(table)));").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            return parts[1]
        })
    }

    private nonisolated func sqliteLines(dbURL: URL, sql: String) -> [String] {
        let result = ProcessRunnerResult.run(
            "/usr/bin/sqlite3",
            arguments: ["-readonly", "-separator", "\t", dbURL.path, sql]
        )
        guard result.status == 0 else { return [] }
        return result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated func firstExisting(_ candidates: [String], in columns: Set<String>) -> String? {
        candidates.first { columns.contains($0) }
    }

    private nonisolated func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private nonisolated func sqlStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private nonisolated func dingTalkIdentifierFilterSQL(identifierExpression: String) -> String {
        let exactList = dingTalkBundleIDs.map(sqlStringLiteral).joined(separator: ", ")
        let lowercaseIdentifier = "lower(\(identifierExpression))"
        return """
        (
          \(identifierExpression) IN (\(exactList))
          OR \(lowercaseIdentifier) LIKE '%dingtalk%'
          OR \(lowercaseIdentifier) LIKE '%rimet%'
        )
        """
    }

    private nonisolated func extractStrings(fromHex hex: String) -> [String] {
        guard let data = Data(hexString: hex), !data.isEmpty else { return [] }
        var values: [String] = []
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            collectStrings(from: plist, into: &values)
        }
        values.append(contentsOf: printableStrings(in: data))
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }

    private nonisolated func collectStrings(from value: Any, into values: inout [String]) {
        if let string = value as? String {
            values.append(string)
        } else if let data = value as? Data {
            values.append(contentsOf: printableStrings(in: data))
        } else if let array = value as? [Any] {
            array.forEach { collectStrings(from: $0, into: &values) }
        } else if let dictionary = value as? [AnyHashable: Any] {
            dictionary.values.forEach { collectStrings(from: $0, into: &values) }
        }
    }

    private nonisolated func printableStrings(in data: Data) -> [String] {
        var strings: [String] = []
        var current = [UInt8]()
        for byte in data {
            if byte >= 32, byte <= 126 {
                current.append(byte)
            } else {
                appendASCIIString(&current, to: &strings)
            }
        }
        appendASCIIString(&current, to: &strings)

        let utf16 = String(data: data, encoding: .utf16LittleEndian) ?? ""
        let pieces = utf16
            .components(separatedBy: CharacterSet.controlCharacters.union(.newlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0.count <= 180 }
        strings.append(contentsOf: pieces)
        return strings
    }

    private nonisolated func appendASCIIString(_ bytes: inout [UInt8], to strings: inout [String]) {
        defer { bytes.removeAll(keepingCapacity: true) }
        guard bytes.count >= 3,
              let string = String(bytes: bytes, encoding: .utf8)
        else {
            return
        }
        strings.append(string)
    }

    private nonisolated func bestMessage(from strings: [String], excluding excluded: [String]) -> (title: String, body: String) {
        let filtered = strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isUsefulMessageString($0, excluding: excluded) }

        guard let title = filtered.first else {
            return ("", "")
        }
        let body = filtered.dropFirst().first ?? ""
        return (title, body)
    }

    private nonisolated func isUsefulMessageString(_ value: String, excluding excluded: [String]) -> Bool {
        guard value.count >= 2, value.count <= 180 else { return false }
        if excluded.contains(where: { value.contains($0) }) { return false }
        if value.hasPrefix("com.") || value.hasPrefix("UN") || value.hasPrefix("NS") { return false }
        if value.contains("Notification") || value.contains("NSDictionary") || value.contains("NSString") { return false }
        if value.contains("http://") || value.contains("https://") { return false }
        if value.range(of: #"^[0-9A-Fa-f-]{16,}$"#, options: .regularExpression) != nil { return false }
        return true
    }
}

private struct MacNotificationRecord {
    let id: String
    let title: String
    let body: String
    let sortKey: Double
}

private struct BridgeReadSnapshot {
    let candidatePaths: [String]
    let matchedAppIdentifiers: [String]
    let matchedRowCount: Int
    let records: [MacNotificationRecord]
}

private struct DatabaseReadResult {
    let records: [MacNotificationRecord]
    let matchedAppIdentifiers: [String]
    let matchedRowCount: Int

    static let empty = DatabaseReadResult(
        records: [],
        matchedAppIdentifiers: [],
        matchedRowCount: 0
    )
}

private enum BridgeReadResult {
    case records(BridgeReadSnapshot)
    case permissionDenied
    case notFound
}

private enum DatabaseDiscoveryResult {
    case success([URL])
    case permissionDenied
}

private enum ProcessRunnerResult {
    static func run(_ executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (127, "\(error)")
        }
    }
}

private extension Data {
    init?(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
            guard next <= hexString.endIndex,
                  let byte = UInt8(hexString[index..<next], radix: 16)
            else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
