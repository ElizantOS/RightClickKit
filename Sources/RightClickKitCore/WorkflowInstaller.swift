import Foundation

public struct WorkflowInstaller {
    public static let managedMarkerKey = "RightClickKitManaged"
    public static let managedMarkerValue = "true"

    public let paths: RCKPaths
    public let fileManager: FileManager
    public let refreshAfterChanges: Bool

    public init(
        paths: RCKPaths = RCKPaths(),
        fileManager: FileManager = .default,
        refreshAfterChanges: Bool = ProcessInfo.processInfo.environment["RIGHTCLICKKIT_SKIP_REFRESH"] != "1"
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.refreshAfterChanges = refreshAfterChanges
    }

    public func install(services: [ServiceDefinition], rckPath: String) throws -> [URL] {
        try fileManager.createDirectory(at: paths.userServicesDirectory, withIntermediateDirectories: true)

        let enabledServices = services.filter(\.enabled)
        let targetWorkflowPaths = Set(enabledServices.map { paths.workflowURL(title: $0.title).standardizedFileURL.path })
        let existingWorkflows = try existingManagedWorkflows()
        for workflow in existingWorkflows
            where !targetWorkflowPaths.contains(workflow.standardizedFileURL.path) {
            try fileManager.removeItem(at: workflow)
        }

        var installed: [URL] = []
        for service in enabledServices {
            let workflowURL = paths.workflowURL(title: service.title)
            if fileManager.fileExists(atPath: workflowURL.path) {
                guard isManagedWorkflow(workflowURL) else {
                    throw RightClickKitError.unmanagedWorkflowExists(workflowURL)
                }
                try fileManager.removeItem(at: workflowURL)
            }

            try writeWorkflow(service: service, rckPath: rckPath, workflowURL: workflowURL)
            installed.append(workflowURL)
        }

        if refreshAfterChanges {
            refreshFinderServices()
        }
        return installed
    }

    public func uninstallManagedWorkflows() throws -> [URL] {
        let workflows = try existingManagedWorkflows()
        for workflow in workflows {
            try fileManager.removeItem(at: workflow)
        }

        if refreshAfterChanges {
            refreshFinderServices()
        }
        return workflows
    }

    private func existingManagedWorkflows() throws -> [URL] {
        guard fileManager.fileExists(atPath: paths.userServicesDirectory.path) else {
            return []
        }

        let workflows = try fileManager.contentsOfDirectory(
            at: paths.userServicesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "workflow" }

        return workflows.filter { isManagedWorkflow($0) }
    }

    public func isManagedWorkflow(_ workflowURL: URL) -> Bool {
        let infoURL = workflowURL.appendingPathComponent("Contents/Info.plist")
        guard
            let plist = NSDictionary(contentsOf: infoURL),
            let value = plist[Self.managedMarkerKey] as? String
        else {
            return false
        }
        return value == Self.managedMarkerValue
    }

    private func writeWorkflow(service: ServiceDefinition, rckPath: String, workflowURL: URL) throws {
        let contentsURL = workflowURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let info = infoPlist(service: service)
        try info.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let document = documentWflow(service: service, rckPath: rckPath)
        try document.write(
            to: resourcesURL.appendingPathComponent("document.wflow"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func infoPlist(service: ServiceDefinition) -> String {
        let title = XML.escape(service.title)
        let bundleID = XML.escape("dev.rightclickkit.\(service.id)")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleDevelopmentRegion</key>
          <string>en</string>
          <key>CFBundleIdentifier</key>
          <string>\(bundleID)</string>
          <key>CFBundleName</key>
          <string>\(title)</string>
          <key>CFBundleShortVersionString</key>
          <string>1.0</string>
          <key>\(Self.managedMarkerKey)</key>
          <string>\(Self.managedMarkerValue)</string>
          <key>RightClickKitServiceID</key>
          <string>\(XML.escape(service.id))</string>
          <key>NSServices</key>
          <array>
            <dict>
              <key>NSMenuItem</key>
              <dict>
                <key>default</key>
                <string>\(title)</string>
              </dict>
              <key>NSMessage</key>
              <string>runWorkflowAsService</string>
              <key>NSSendFileTypes</key>
              <array>
                <string>public.item</string>
              </array>
            </dict>
          </array>
        </dict>
        </plist>
        """
    }

    private func documentWflow(service: ServiceDefinition, rckPath: String) -> String {
        let serviceID = service.id
        let command = """
        log_dir="$HOME/Library/Logs/RightClickKit"
        mkdir -p "$log_dir"
        launcher_log="$log_dir/\(serviceID).launcher.log"

        items=("$@")
        if [[ ${#items[@]} -eq 0 && ! -t 0 ]]; then
          while IFS= read -r item; do
            [[ -n "$item" ]] && items+=("$item")
          done
        fi

        rck=\(Shell.quote(rckPath))
        {
          echo
          echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] launch \(serviceID)"
          echo "rck: $rck"
          printf 'items:'
          for item in "${items[@]}"; do
            printf ' <%s>' "$item"
          done
          printf '\\n'
        } >> "$launcher_log"

        if [[ ! -x "$rck" ]]; then
          echo "missing executable: $rck" >> "$launcher_log"
          /usr/bin/osascript -e 'display alert "RightClickKit" message "Missing rck executable: \(rckPath)" as critical' >/dev/null 2>&1 || true
          exit 127
        fi

        "$rck" run \(Shell.quote(service.id)) "${items[@]}" >> "$launcher_log" 2>&1
        status=$?
        echo "exit: $status" >> "$launcher_log"
        exit "$status"
        """

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>AMApplicationBuild</key>
          <string>521</string>
          <key>AMApplicationVersion</key>
          <string>2.10</string>
          <key>AMDocumentVersion</key>
          <string>2</string>
          <key>actions</key>
          <array>
            <dict>
              <key>action</key>
              <dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                  <key>CheckedForUserDefaultShell</key>
                  <true/>
                  <key>COMMAND_STRING</key>
                  <string>\(XML.escape(command))</string>
                  <key>inputMethod</key>
                  <integer>1</integer>
                  <key>shell</key>
                  <string>/bin/zsh</string>
                  <key>source</key>
                  <string>\(XML.escape(command))</string>
                </dict>
                <key>AMAccepts</key>
                <dict>
                  <key>Container</key>
                  <string>List</string>
                  <key>Optional</key>
                  <true/>
                  <key>Types</key>
                  <array>
                    <string>com.apple.cocoa.path</string>
                  </array>
                </dict>
                <key>AMActionVersion</key>
                <string>2.0.3</string>
                <key>AMProvides</key>
                <dict>
                  <key>Container</key>
                  <string>List</string>
                  <key>Types</key>
                  <array>
                    <string>com.apple.cocoa.string</string>
                  </array>
                </dict>
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>UUID</key>
                <string>07ED17BF-948F-4C86-9A2D-765B2D3F1A8C</string>
              </dict>
            </dict>
          </array>
          <key>connectors</key>
          <dict/>
          <key>workflowMetaData</key>
          <dict>
            <key>serviceApplicationBundleID</key>
            <string>com.apple.finder</string>
            <key>serviceInputTypeIdentifier</key>
            <string>com.apple.Automator.fileSystemObject</string>
            <key>serviceOutputTypeIdentifier</key>
            <string>com.apple.Automator.nothing</string>
            <key>serviceProcessesInput</key>
            <integer>0</integer>
            <key>workflowTypeIdentifier</key>
            <string>com.apple.Automator.servicesMenu</string>
          </dict>
        </dict>
        </plist>
        """
    }

    private func refreshFinderServices() {
        _ = ProcessRunner.runQuiet("/System/Library/CoreServices/pbs", arguments: ["-flush"])
        _ = ProcessRunner.runQuiet("/usr/bin/killall", arguments: ["Finder"])
    }
}
