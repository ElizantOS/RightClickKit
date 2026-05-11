import Foundation

public enum ActionScriptGenerator {
    public static func generate(_ action: ActionConfig) -> String {
        generate(action, registry: .builtIn)
    }

    public static func generate(_ action: ActionConfig, registry: ActionRegistry) -> String {
        let manifest = registry.manifest(for: action.type)
        return generate(action, manifest: manifest)
    }

    public static func generate(_ action: ActionConfig, manifest: ActionManifest) -> String {
        switch manifest.entryPoint {
        case let .nativeTool(tool):
            return nativeToolScript(tool: tool)
        case .agent:
            return """
            #!/bin/zsh
            echo "RightClickKit agent actions are not wired yet." >&2
            exit 64
            """
        case .script:
            return """
            #!/bin/zsh
            \(action.command)
            """
        case .workflow:
            return """
            #!/bin/zsh
            echo "RightClickKit workflow actions are not wired yet." >&2
            exit 64
            """
        case let .builtIn(type):
            return generateBuiltIn(action, type: type)
        }
    }

    private static func generateBuiltIn(_ action: ActionConfig, type: ActionType) -> String {
        switch type {
        case .openWithApp:
            let bundleID = action.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bundleID.isEmpty {
                return """
                #!/bin/zsh
                open -b \(Shell.quote(bundleID)) "$@"
                """
            }
            return """
            #!/bin/zsh
            open -a \(Shell.quote(action.appName)) "$@"
            """

        case .openWithCodeEditor:
            let command = action.codeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                return """
                #!/bin/zsh
                \(Shell.quote(command)) "$@"
                """
            }
            return generate(ActionConfig(
                type: .openWithApp,
                appName: action.appName,
                bundleID: action.bundleID,
                codeCommand: "",
                terminalApp: action.terminalApp,
                command: action.command,
                pathFormat: action.pathFormat
            ))

        case .openTerminalHere:
            return """
            #!/bin/zsh
            open -a \(Shell.quote(action.terminalApp)) "$PWD"
            """

        case .copyPaths:
            switch action.pathFormat {
            case .lines:
                return """
                #!/bin/zsh
                printf '%s\\n' "$@" | pbcopy
                """
            case .spaces:
                return """
                #!/bin/zsh
                printf '%s ' "$@" | pbcopy
                """
            case .json:
                return """
                #!/bin/zsh
                printf '[' > /tmp/rightclickkit-paths-json.$$
                first=1
                for item in "$@"; do
                  escaped=${item//\\\\/\\\\\\\\}
                  escaped=${escaped//\\"/\\\\\\"}
                  if [[ $first -eq 0 ]]; then
                    printf ',' >> /tmp/rightclickkit-paths-json.$$
                  fi
                  first=0
                  printf '"%s"' "$escaped" >> /tmp/rightclickkit-paths-json.$$
                done
                printf ']' >> /tmp/rightclickkit-paths-json.$$
                pbcopy < /tmp/rightclickkit-paths-json.$$
                rm -f /tmp/rightclickkit-paths-json.$$
                """
            }

        case .runCommand:
            return """
            #!/bin/zsh
            \(action.command)
            """

        case .showDirectoryTree:
            return nativeToolScript(tool: .directoryTree)

        case .analyzeStorage:
            return nativeToolScript(tool: .storageAnalysis)
        }
    }

    private static func nativeToolScript(tool: NativeToolID) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        rck="${RCK_HELPER:-$HOME/.rightclickkit/bin/rck}"
        if [[ ! -x "$rck" ]]; then
          echo "missing rck executable: $rck" >&2
          exit 127
        fi

        "$rck" action run \(Shell.quote(tool.rawValue)) "$@"
        """
    }
}
