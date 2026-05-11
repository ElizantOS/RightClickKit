import RightClickKitCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var selectedID: String?

    private var selectedAction: EditableAction? {
        model.actions.first { $0.id == selectedID } ?? model.actions.first
    }

    var body: some View {
        NavigationSplitView {
            List(model.actions, selection: $selectedID) { action in
                SidebarActionRow(action: action)
                    .tag(action.id)
            }
            .listStyle(.sidebar)
            .navigationTitle("Right-click Actions")
            .toolbar {
                Button {
                    model.reload()
                    model.reloadInstalledApps()
                    selectedID = selectedAction?.id ?? model.actions.first?.id
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload services and installed apps")
            }
        } detail: {
            if let selectedAction {
                ActionDetailView(action: selectedAction, model: model)
            } else {
                ContentUnavailableView(
                    "No Actions",
                    systemImage: "cursorarrow.click",
                    description: Text("Add a service under services/<id>/service.yaml.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom) {
            RCKGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Label(model.status, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Button {
                        model.install()
                    } label: {
                        Label("Install Enabled", systemImage: "checkmark.circle")
                    }
                    .rckGlassButton(prominent: true)

                    Button {
                        model.uninstall()
                    } label: {
                        Label("Uninstall Managed", systemImage: "trash")
                    }
                    .rckGlassButton()

                    Button {
                        model.openLogs()
                    } label: {
                        Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    .rckGlassButton()
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .rckGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    interactive: true
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            model.reload()
            model.reloadInstalledApps()
            selectedID = model.actions.first?.id
        }
    }
}

struct SidebarActionRow: View {
    @ObservedObject var action: EditableAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .lineLimit(1)
                Text("\(typeTitle) • \(action.status.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var typeTitle: String {
        action.mode == .action ? action.action.type.title : "Raw Script"
    }

    private var iconName: String {
        action.mode == .action ? action.action.type.systemImage : "terminal"
    }
}

struct ActionDetailView: View {
    @ObservedObject var action: EditableAction
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            RCKGlassGroup(spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    ActionStatusView(action: action, model: model)
                    ActionBuilderView(action: action, model: model)
                    LogsPanelView(action: action, model: model)
                    AdvancedPanelView(action: action)
                }
                .padding(18)
            }
        }
    }
}
