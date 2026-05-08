import SwiftUI

struct AppPickerView: View {
    let installedApps: [InstalledApp]
    let onSelect: (InstalledApp) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Choose App")
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Menu("Installed Apps") {
                if installedApps.isEmpty {
                    Text("No apps found")
                } else {
                    ForEach(installedApps) { app in
                        Button {
                            onSelect(app)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(app.name)
                                if !app.bundleIdentifier.isEmpty {
                                    Text(app.bundleIdentifier)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 180)
            Text("Auto-fills name and bundle id when available.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
