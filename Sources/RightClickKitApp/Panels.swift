import RightClickKitCore
import SwiftUI

struct LogsPanelView: View {
    @ObservedObject var action: EditableAction
    @ObservedObject var model: AppModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Refresh") { model.loadLog(for: action) }
                    Button("Repair Helper") { model.repairHelper() }
                    Button("Reinstall Action") { model.saveAndInstall(action) }
                    Button("Open Logs Folder") { model.openLogs() }
                    Spacer()
                }
                TextEditor(text: $action.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .border(Color.secondary.opacity(0.25))
            }
            .padding(.top, 8)
        } label: {
            Label("Logs", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AdvancedPanelView: View {
    @ObservedObject var action: EditableAction
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(action.mode == .action ? "Generated script" : "Raw script")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if action.mode == .action {
                    GeneratedScriptView(script: action.scriptText)
                } else {
                    HighlightedTextEditor(text: $action.rawScript, language: .shell)
                        .frame(minHeight: 220)
                }

                Text("service.yaml")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeneratedYAMLView(text: action.yamlText)
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct GeneratedScriptView: View {
    @State var script: String

    var body: some View {
        HighlightedTextEditor(text: $script, language: .shell, isReadOnly: true)
            .frame(minHeight: 180)
    }
}

private struct GeneratedYAMLView: View {
    @State var text: String

    var body: some View {
        HighlightedTextEditor(text: $text, language: .yaml, isReadOnly: true)
            .frame(minHeight: 180)
    }
}
