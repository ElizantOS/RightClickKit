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
                    Button {
                        model.loadLog(for: action)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .rckGlassButton()

                    Button {
                        model.repairHelper()
                    } label: {
                        Label("Repair Helper", systemImage: "wrench.and.screwdriver")
                    }
                    .rckGlassButton()

                    Button {
                        model.saveAndInstall(action)
                    } label: {
                        Label("Reinstall Action", systemImage: "arrow.down.circle")
                    }
                    .rckGlassButton(prominent: true)

                    Button {
                        model.openLogs()
                    } label: {
                        Label("Open Logs Folder", systemImage: "folder")
                    }
                    .rckGlassButton()

                    Spacer()
                }
                .controlSize(.small)

                TextEditor(text: $action.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.top, 8)
        } label: {
            Label("Logs", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
        }
        .padding(14)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
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
                        .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    HighlightedTextEditor(text: $action.rawScript, language: .shell)
                        .frame(minHeight: 220)
                        .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text("service.yaml")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeneratedYAMLView(text: action.yamlText)
                    .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
        }
        .padding(14)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private struct GeneratedScriptView: View {
    let script: String

    var body: some View {
        HighlightedTextEditor(text: .constant(script), language: .shell, isReadOnly: true)
            .frame(minHeight: 180)
    }
}

private struct GeneratedYAMLView: View {
    let text: String

    var body: some View {
        HighlightedTextEditor(text: .constant(text), language: .yaml, isReadOnly: true)
            .frame(minHeight: 180)
    }
}
