import Foundation

public enum YAMLServiceCodec {
    public static func load(from yamlURL: URL) throws -> ServiceDefinition {
        let text = try String(contentsOf: yamlURL, encoding: .utf8)
        let values = parseKeyValues(text)
        let directory = yamlURL.deletingLastPathComponent()

        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else {
                throw RightClickKitError.missingField(key, yamlURL)
            }
            return value
        }

        let id = try required("id")
        let title = try required("title")
        let description = values["description"] ?? ""
        let acceptsText = try required("accepts")
        let accepts = try parseAccepts(acceptsText, yamlURL: yamlURL)
        let shell = values["shell"] ?? "/bin/zsh"
        let script = values["script"] ?? "action.zsh"
        let enabled = parseBool(values["enabled"] ?? "true")
        let confirm = parseBool(values["confirm"] ?? "false")
        let mode = ServiceMode(rawValue: values["mode"] ?? "") ?? (values["type"] == nil ? .rawScript : .action)
        let action = mode == .action ? parseAction(values) : nil

        return ServiceDefinition(
            id: id,
            title: title,
            description: description,
            accepts: accepts,
            shell: shell,
            script: script,
            enabled: enabled,
            confirm: confirm,
            mode: mode,
            action: action,
            directory: directory
        )
    }

    public static func dump(_ service: ServiceDefinition) -> String {
        let accepts = service.accepts.map(\.rawValue).joined(separator: ", ")
        var text = """
        id: \(yamlScalar(service.id))
        title: \(yamlScalar(service.title))
        description: \(yamlScalar(service.description))
        accepts: [\(accepts)]
        shell: \(yamlScalar(service.shell))
        script: \(yamlScalar(service.script))
        enabled: \(service.enabled ? "true" : "false")
        confirm: \(service.confirm ? "true" : "false")
        mode: \(service.mode.rawValue)
        """
        if let action = service.action, service.mode == .action {
            text += """

            action:
              type: \(action.type.rawValue)
              appName: \(yamlScalar(action.appName))
              bundleID: \(yamlScalar(action.bundleID))
              codeCommand: \(yamlScalar(action.codeCommand))
              terminalApp: \(yamlScalar(action.terminalApp))
              command: \(yamlScalar(action.command))
              pathFormat: \(action.pathFormat.rawValue)
            """
        }
        return text
    }

    private static func parseKeyValues(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let lineWithoutComment = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !lineWithoutComment.isEmpty else { continue }
            guard let colon = lineWithoutComment.firstIndex(of: ":") else { continue }
            let key = lineWithoutComment[..<colon].trimmingCharacters(in: .whitespaces)
            var value = lineWithoutComment[lineWithoutComment.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            value = unquote(value)
            result[key] = value
        }
        return result
    }

    private static func parseAccepts(_ text: String, yamlURL: URL) throws -> [ServiceAccepts] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let inner: String
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            inner = String(trimmed.dropFirst().dropLast())
        } else {
            inner = trimmed
        }

        let parts = inner
            .split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        let accepts = parts.compactMap(ServiceAccepts.init(rawValue:))
        guard accepts.count == parts.count, !accepts.isEmpty else {
            throw RightClickKitError.invalidValue("accepts must contain file and/or folder", yamlURL)
        }
        return accepts
    }

    private static func parseBool(_ text: String) -> Bool {
        ["true", "yes", "1", "on"].contains(text.lowercased())
    }

    private static func parseAction(_ values: [String: String]) -> ActionConfig {
        let type = ActionType(rawValue: values["type"] ?? "") ?? .openWithApp
        let format = CopyPathsFormat(rawValue: values["pathFormat"] ?? "") ?? .lines
        return ActionConfig(
            type: type,
            appName: values["appName"] ?? "Cursor",
            bundleID: values["bundleID"] ?? "",
            codeCommand: values["codeCommand"] ?? "/usr/local/bin/code",
            terminalApp: values["terminalApp"] ?? "Terminal",
            command: values["command"] ?? "pwd && ls -la",
            pathFormat: format
        )
    }

    private static func stripComment(_ line: String) -> String {
        var inSingleQuote = false
        var inDoubleQuote = false
        for (offset, character) in line.enumerated() {
            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if character == "#" && !inSingleQuote && !inDoubleQuote {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    private static func unquote(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("\"") && result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
            result = result.replacingOccurrences(of: #"\""#, with: #"""#)
            result = result.replacingOccurrences(of: #"\\n"#, with: "\n")
            result = result.replacingOccurrences(of: #"\\\\"#, with: #"\"#)
        } else if result.hasPrefix("'") && result.hasSuffix("'") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private static func yamlScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = ["true", "false", "yes", "no", "on", "off", "null", "~"]
        let needsQuotes = value.isEmpty ||
            value != trimmed ||
            value.contains(":") ||
            value.contains("#") ||
            value.contains("[") ||
            value.contains("]") ||
            value.contains("{") ||
            value.contains("}") ||
            value.contains(",") ||
            value.contains("\"") ||
            value.contains("'") ||
            value.contains("\\") ||
            value.contains("\n") ||
            reserved.contains(value.lowercased())

        guard needsQuotes else {
            return value
        }

        let escaped = value
            .replacingOccurrences(of: #"\"#, with: #"\\\\"#)
            .replacingOccurrences(of: "\n", with: #"\\n"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        return "\"\(escaped)\""
    }
}
