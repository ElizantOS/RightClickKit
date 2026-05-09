import AppKit
import SwiftUI

struct TreeViewerRootView: View {
    @StateObject private var model: TreeScanModel

    init(request: TreeViewerRequest) {
        _model = StateObject(wrappedValue: TreeScanModel(request: request))
    }

    var body: some View {
        Group {
            switch model.phase {
            case let .scanning(title):
                TreeLoadingView(title: title)
            case let .displaying(snapshot):
                TreeViewerView(snapshot: snapshot, model: model)
            case let .failed(message):
                TreeErrorView(message: message)
            }
        }
        .task {
            model.start()
        }
    }
}

struct TreeViewerView: View {
    let snapshot: DirectoryTreeSnapshot
    @ObservedObject var model: TreeScanModel
    @State private var selectedID: String?
    @State private var expandedIDs: Set<String> = []

    private var root: DirectoryTreeNode {
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return snapshot.root
        }
        return snapshot.root.filtered(matching: model.query) ?? snapshot.root
    }

    private var selectedNode: DirectoryTreeNode {
        root.find(id: selectedID) ?? root
    }

    var body: some View {
        RCKGlassGroup(spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                TreeHeaderView(snapshot: snapshot, root: root, model: model)

                HStack(spacing: 16) {
                    TreeOutlinePanel(
                        root: root,
                        selectedID: $selectedID,
                        expandedIDs: $expandedIDs,
                        loadingNodeIDs: model.loadingNodeIDs,
                        onExpand: model.expandIfNeeded
                    )
                    .frame(minWidth: 310, idealWidth: 360, maxWidth: 420)

                    TreeTextPanel(root: root, model: model)
                        .frame(minWidth: 360, maxWidth: .infinity)

                    TreeInspectorPanel(
                        snapshot: snapshot,
                        node: selectedNode,
                        model: model
                    )
                    .frame(width: 330)
                }
            }
        }
        .padding(24)
        .onAppear {
            expandedIDs.insert(root.id)
            if selectedID == nil {
                selectedID = root.id
            }
        }
        .onChange(of: snapshot.root.id) { _, _ in
            expandedIDs.insert(root.id)
            selectedID = root.id
        }
    }
}

private struct TreeHeaderView: View {
    let snapshot: DirectoryTreeSnapshot
    let root: DirectoryTreeNode
    @ObservedObject var model: TreeScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TreePalette.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text(root.name)
                        .font(.system(size: 25, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(root.path)
                        .font(.system(size: 12))
                        .foregroundStyle(TreePalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                TreeScanBadge(snapshot: snapshot)
            }

            HStack(spacing: 12) {
                TextField("Search files and folders", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)

                Toggle("Hidden", isOn: $model.options.includeHidden)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.options.includeHidden) { _, _ in model.rescan() }

                Toggle("Packages", isOn: $model.options.includePackages)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.options.includePackages) { _, _ in model.rescan() }

                Stepper("Outline \(model.options.maxDepth)", value: $model.options.maxDepth, in: 1...10)
                    .onChange(of: model.options.maxDepth) { _, _ in model.rescan() }

                Spacer()

                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .rckGlassButton()
            }
            .controlSize(.small)
        }
    }
}

private struct TreeScanBadge: View {
    let snapshot: DirectoryTreeSnapshot

    private var iconName: String {
        if !snapshot.isComplete { return "arrow.triangle.2.circlepath" }
        return snapshot.truncated ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var title: String {
        if !snapshot.isComplete { return "Scanning" }
        return snapshot.truncated ? "Limited" : "Complete"
    }

    private var tint: Color {
        if !snapshot.isComplete { return TreePalette.blue }
        return snapshot.truncated ? TreePalette.warning : TreePalette.secondaryText
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text("\(TreeFormatter.count(snapshot.scannedEntries))/\(TreeFormatter.count(snapshot.maxEntries))")
                .font(.system(size: 12))
                .foregroundStyle(TreePalette.secondaryText)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .rckGlassSurface(in: Capsule())
    }
}

private struct TreeOutlinePanel: View {
    let root: DirectoryTreeNode
    @Binding var selectedID: String?
    @Binding var expandedIDs: Set<String>
    let loadingNodeIDs: Set<String>
    var onExpand: (DirectoryTreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Directory Tree", systemImage: "sidebar.left")
                .font(.system(size: 15, weight: .semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    TreeOutlineRow(
                        node: root,
                        selectedID: $selectedID,
                        expandedIDs: $expandedIDs,
                        loadingNodeIDs: loadingNodeIDs,
                        onExpand: onExpand
                    )
                }
                .padding(.trailing, 8)
            }
        }
        .padding(16)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private struct TreeOutlineRow: View {
    let node: DirectoryTreeNode
    @Binding var selectedID: String?
    @Binding var expandedIDs: Set<String>
    let loadingNodeIDs: Set<String>
    var onExpand: (DirectoryTreeNode) -> Void

    private var isExpanded: Bool {
        expandedIDs.contains(node.id)
    }

    private var isSelected: Bool {
        selectedID == node.id
    }

    private var isLoading: Bool {
        loadingNodeIDs.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                selectedID = node.id
                if node.isDirectory {
                    toggleExpanded()
                }
            } label: {
                HStack(spacing: 7) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12)
                    } else {
                        Image(systemName: node.isDirectory && isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(node.isDirectory ? TreePalette.secondaryText : .clear)
                            .frame(width: 12)
                    }

                    Image(systemName: node.kind.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TreePalette.depthColor(node.depth))
                        .frame(width: 16)

                    Text(node.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    if node.isDirectory {
                        Text(TreeFormatter.count(node.childCount))
                            .font(.system(size: 11))
                            .foregroundStyle(TreePalette.secondaryText)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, CGFloat(node.depth) * 14)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? TreePalette.blue.opacity(0.16) : Color.clear)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(node.children) { child in
                    TreeOutlineRow(
                        node: child,
                        selectedID: $selectedID,
                        expandedIDs: $expandedIDs,
                        loadingNodeIDs: loadingNodeIDs,
                        onExpand: onExpand
                    )
                }
            }
        }
    }

    private func toggleExpanded() {
        if expandedIDs.contains(node.id) {
            expandedIDs.remove(node.id)
        } else {
            expandedIDs.insert(node.id)
            if node.children.isEmpty {
                onExpand(node)
            }
        }
    }
}

private struct TreeTextPanel: View {
    let root: DirectoryTreeNode
    @ObservedObject var model: TreeScanModel

    private var isFiltered: Bool {
        !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayText: String {
        if isFiltered {
            return TreeTextRenderer.text(root, lineLimit: 30_000)
        }

        switch model.treeText {
        case let .ready(text, _, _):
            return text
        case let .loading(message):
            return "\(message)..."
        case let .failed(message):
            let fallback = TreeTextRenderer.text(root, lineLimit: 30_000)
            return fallback + "\n\n# tree command unavailable: \(message)"
        }
    }

    private var lineCount: Int {
        if isFiltered {
            return root.visibleNodeCount(limit: 30_000)
        }
        return model.treeText.lineCount ?? displayText.split(whereSeparator: \.isNewline).count
    }

    private var sourceTitle: String {
        isFiltered ? "filtered" : model.treeText.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tree Text", systemImage: "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Text("\(TreeFormatter.count(lineCount)) lines")
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)

                Text(sourceTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)

                Stepper("Level \(model.options.textDepth)", value: $model.options.textDepth, in: 1...12)
                    .onChange(of: model.options.textDepth) { _, _ in
                        model.reloadTreeText()
                    }
                    .controlSize(.small)

                Button {
                    model.copyTreeText(displayText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .rckGlassButton()
                .controlSize(.small)
            }

            TreePlainTextView(text: displayText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 420)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private struct TreePlainTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView ?? scrollView.documentView as? NSTextView
        guard let textView, textView.string != text else { return }
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
    }

    final class Coordinator {
        weak var textView: NSTextView?
    }
}

private enum TreeTextRenderer {
    static func text(_ root: DirectoryTreeNode, lineLimit: Int) -> String {
        var lines: [String] = [root.name]
        var remaining = max(lineLimit - 1, 0)
        append(root.children, prefix: "", lines: &lines, remaining: &remaining)
        return lines.joined(separator: "\n")
    }

    private static func append(
        _ nodes: [DirectoryTreeNode],
        prefix: String,
        lines: inout [String],
        remaining: inout Int
    ) {
        guard remaining > 0 else { return }

        for (index, node) in nodes.enumerated() {
            guard remaining > 0 else {
                lines.append(prefix + "... more entries")
                return
            }

            let isLast = index == nodes.count - 1
            let branch = isLast ? "└── " : "├── "
            lines.append(prefix + branch + node.name)
            remaining -= 1

            let childPrefix = prefix + (isLast ? "    " : "│   ")
            append(node.children, prefix: childPrefix, lines: &lines, remaining: &remaining)
        }
    }
}
private struct TreeInspectorPanel: View {
    let snapshot: DirectoryTreeSnapshot
    let node: DirectoryTreeNode
    @ObservedObject var model: TreeScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label(node.name, systemImage: node.kind.iconName)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(node.path)
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                TreeMetricTile(value: TreeFormatter.count(node.fileCount), label: "Files", icon: "doc")
                TreeMetricTile(value: TreeFormatter.count(node.folderCount), label: "Folders", icon: "folder")
                TreeMetricTile(value: TreeFormatter.count(node.maxDepth), label: "Depth", icon: "arrow.down.right")
            }

            Divider().overlay(TreePalette.divider)

            VStack(alignment: .leading, spacing: 9) {
                InspectorLine(title: "Kind", value: node.kind.rawValue)
                InspectorLine(title: "Children", value: TreeFormatter.count(node.childCount))
                InspectorLine(title: "Modified", value: TreeFormatter.date(node.modifiedAt))
                InspectorLine(title: "Hidden", value: node.isHidden ? "Yes" : "No")
                InspectorLine(title: "Package", value: node.isPackage ? "Yes" : "No")
            }

            HStack(spacing: 8) {
                Button { model.reveal(node) } label: { Label("Reveal", systemImage: "finder") }
                    .rckGlassButton()
                Button { model.copyPath(node) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .rckGlassButton()
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Button { model.openInCode(node) } label: { Label("Code", systemImage: "curlybraces") }
                    .rckGlassButton()
                Button { model.openTerminal(node) } label: { Label("Terminal", systemImage: "terminal") }
                    .rckGlassButton()
            }
            .controlSize(.small)

            Button {
                model.exportTreeText(snapshot)
            } label: {
                Label("Copy Tree Text", systemImage: "square.and.arrow.up")
            }
            .rckGlassButton(prominent: true)
            .controlSize(.small)

            Spacer()

            TreeFooter(snapshot: snapshot)
        }
        .padding(18)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private struct TreeMetricTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(TreePalette.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(TreePalette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InspectorLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(TreePalette.secondaryText)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

private struct TreeFooter: View {
    let snapshot: DirectoryTreeSnapshot

    private var iconName: String {
        if !snapshot.isComplete { return "arrow.triangle.2.circlepath" }
        return snapshot.truncated ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var title: String {
        if !snapshot.isComplete { return "Scanning" }
        return snapshot.truncated ? "Limited" : "Complete"
    }

    private var tint: Color {
        if !snapshot.isComplete { return TreePalette.blue }
        return snapshot.truncated ? TreePalette.warning : TreePalette.secondaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text("\(TreeFormatter.count(snapshot.scannedEntries)) entries")
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)
            }

            if snapshot.truncated {
                Label("Entry limit reached", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TreePalette.warning)
            }

            if !snapshot.currentPath.isEmpty {
                Text(snapshot.currentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(TreePalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct TreeLoadingView: View {
    let title: String

    var body: some View {
        RCKGlassGroup(spacing: 12) {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(TreePalette.blue)
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                Text("Scanning directory structure")
                    .font(.system(size: 13))
                    .foregroundStyle(TreePalette.secondaryText)
            }
            .padding(28)
            .rckGlassSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TreeErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(TreePalette.warning)
            Text("Directory Tree")
                .font(.system(size: 24, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(TreePalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension DirectoryTreeNode {
    func flattened() -> [DirectoryTreeNode] {
        [self] + children.flatMap { $0.flattened() }
    }

    func flattened(limit: Int) -> [DirectoryTreeNode] {
        guard limit > 0 else { return [] }
        var result: [DirectoryTreeNode] = []
        appendFlattened(limit: limit, into: &result)
        return result
    }

    func visibleNodeCount(limit: Int) -> Int {
        flattened(limit: limit).count
    }

    private func appendFlattened(limit: Int, into result: inout [DirectoryTreeNode]) {
        guard result.count < limit else { return }
        result.append(self)
        for child in children {
            guard result.count < limit else { return }
            child.appendFlattened(limit: limit, into: &result)
        }
    }

    func find(id: String?) -> DirectoryTreeNode? {
        guard let id else { return nil }
        if self.id == id { return self }
        for child in children {
            if let match = child.find(id: id) {
                return match
            }
        }
        return nil
    }

    func filtered(matching query: String) -> DirectoryTreeNode? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return self }

        let matchedChildren = children.compactMap { $0.filtered(matching: needle) }
        let selfMatches = name.localizedCaseInsensitiveContains(needle)
            || path.localizedCaseInsensitiveContains(needle)

        guard selfMatches || !matchedChildren.isEmpty else { return nil }

        var copy = self
        copy.children = matchedChildren
        copy.childCount = matchedChildren.count
        return copy
    }
}
