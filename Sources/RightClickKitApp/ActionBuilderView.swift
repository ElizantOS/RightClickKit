import RightClickKitCore
import SwiftUI

struct ActionStatusView: View {
    @ObservedObject var action: EditableAction
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Menu Name", text: $action.title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                Spacer()
                StatusBadge(status: action.status)
                Toggle("Enabled", isOn: $action.enabled)
                    .toggleStyle(.switch)
                Button {
                    model.save(action)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .rckGlassButton()

                Button {
                    model.saveAndInstall(action)
                } label: {
                    Label("Install", systemImage: "checkmark.circle")
                }
                .rckGlassButton(prominent: true)

                Button {
                    model.test(action)
                } label: {
                    Label("Test", systemImage: "play.circle")
                }
                .rckGlassButton()
            }
            .controlSize(.small)

            TextField("Description", text: $action.description)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

struct StatusBadge: View {
    let status: ServiceStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .installed: .green.opacity(0.18)
        case .notInstalled: .secondary.opacity(0.14)
        case .modified: .orange.opacity(0.18)
        case .error: .red.opacity(0.18)
        }
    }
}

struct ActionBuilderView: View {
    @ObservedObject var action: EditableAction
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Configure", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Picker("Action Type", selection: action.actionTypeBinding) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .frame(width: 300)
                .disabled(action.mode == .rawScript)
                Toggle("Raw Script", isOn: Binding(
                    get: { action.mode == .rawScript },
                    set: { action.mode = $0 ? .rawScript : .action }
                ))
                .toggleStyle(.switch)
            }

            HStack(spacing: 16) {
                Toggle("Files", isOn: $action.acceptsFile)
                Toggle("Folders", isOn: $action.acceptsFolder)
            }

            if action.mode == .action {
                ActionFieldsView(action: action, installedApps: model.installedApps)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw scripts are for advanced actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HighlightedTextEditor(text: $action.rawScript, language: .shell)
                        .frame(minHeight: 300)
                        .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(16)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

struct ActionFieldsView: View {
    @ObservedObject var action: EditableAction
    let installedApps: [InstalledApp]

    var body: some View {
        switch action.action.type {
        case .openWithApp:
            VStack(alignment: .leading, spacing: 10) {
                AppPickerView(installedApps: installedApps) { app in
                    action.action.appName = app.name
                    action.action.bundleID = app.bundleIdentifier
                }
                FieldRow(title: "App Name") {
                    TextField("Cursor", text: $action.action.appName)
                }
                FieldRow(title: "Bundle ID") {
                    TextField("Optional", text: $action.action.bundleID)
                }
            }
        case .openWithCodeEditor:
            VStack(alignment: .leading, spacing: 10) {
                FieldRow(title: "Code Command") {
                    TextField("/usr/local/bin/code", text: $action.action.codeCommand)
                }
                Text("Tip: Cursor often installs /usr/local/bin/code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .openTerminalHere:
            VStack(alignment: .leading, spacing: 10) {
                AppPickerView(installedApps: installedApps) { app in
                    action.action.terminalApp = app.name
                }
                FieldRow(title: "Terminal App") {
                    TextField("Terminal", text: $action.action.terminalApp)
                }
            }
        case .copyPaths:
            FieldRow(title: "Format") {
                Picker("Format", selection: action.pathFormatBinding) {
                    ForEach(CopyPathsFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
        case .runCommand:
            FieldRow(title: "Command") {
                TextField("pwd && ls -la", text: $action.action.command)
                    .font(.system(.body, design: .monospaced))
            }
            Text("Runs in the selected folder, or the parent folder of the selected file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .showDirectoryTree:
            FieldRow(title: "Report") {
                Text("Interactive directory map")
                    .foregroundStyle(.secondary)
            }
        case .analyzeStorage:
            FieldRow(title: "Report") {
                Text("Interactive storage map")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            content
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)
            Spacer()
        }
    }
}
