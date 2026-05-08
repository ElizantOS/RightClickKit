import Foundation

public enum ActionScriptGenerator {
    public static func generate(_ action: ActionConfig) -> String {
        switch action.type {
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
            return reportScript(kind: "directory-tree")

        case .analyzeStorage:
            return reportScript(kind: "storage-analysis")
        }
    }

    private static func reportScript(kind: String) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        rck="${RCK_HELPER:-}"
        if [[ -z "$rck" ]]; then
          rck="$HOME/.rightclickkit/bin/rck"
        fi

        "$rck" report \(kind) "$@"
        """
    }
}
