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
                TextField("Search files and folders", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    .onChange(of: model.searchText) { _, _ in
                        model.scheduleSearch()
                    }

                Toggle("Hidden", isOn: $model.options.includeHidden)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.options.includeHidden) { _, _ in model.rescan() }

                Toggle("Packages", isOn: $model.options.includePackages)
                    .toggleStyle(.checkbox)
                    .onChange(of: model.options.includePackages) { _, _ in model.rescan() }

                TreeCompactStepper(
                    title: "Outline",
                    value: $model.options.maxDepth,
                    range: 1...10
                ) {
                    model.rescan()
                }

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

private struct TreeCompactStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text("\(title) \(value)")
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Stepper("", value: $value, in: range)
                .labelsHidden()
                .fixedSize()
        }
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: value) { _, _ in
            onChange()
        }
    }
}

private struct TreePanelTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .layoutPriority(2)
        .fixedSize(horizontal: true, vertical: false)
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

            TreeOutlineView(
                root: root,
                selectedID: $selectedID,
                expandedIDs: $expandedIDs,
                loadingNodeIDs: loadingNodeIDs,
                onExpand: onExpand
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .rckGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true
        )
    }
}

private struct TreeOutlineView: NSViewRepresentable {
    let root: DirectoryTreeNode
    @Binding var selectedID: String?
    @Binding var expandedIDs: Set<String>
    let loadingNodeIDs: Set<String>
    var onExpand: (DirectoryTreeNode) -> Void

    init(
        root: DirectoryTreeNode,
        selectedID: Binding<String?>,
        expandedIDs: Binding<Set<String>>,
        loadingNodeIDs: Set<String>,
        onExpand: @escaping (DirectoryTreeNode) -> Void
    ) {
        self.root = root
        self._selectedID = selectedID
        self._expandedIDs = expandedIDs
        self.loadingNodeIDs = loadingNodeIDs
        self.onExpand = onExpand
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedID: $selectedID, expandedIDs: $expandedIDs, onExpand: onExpand)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 26
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.indentationPerLevel = 14
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = false
        outlineView.floatsGroupRows = false
        outlineView.backgroundColor = .clear
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: .treeOutlineColumn)
        column.resizingMask = .autoresizingMask
        column.minWidth = 220
        column.width = 340
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        context.coordinator.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        context.coordinator.update(
            root: root,
            selectedID: selectedID,
            expandedIDs: expandedIDs,
            loadingNodeIDs: loadingNodeIDs,
            outlineView: outlineView
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private var rootItem: TreeOutlineItem?
        private var itemsByID: [String: TreeOutlineItem] = [:]
        private var lastRoot: DirectoryTreeNode?
        private var loadingNodeIDs: Set<String> = []
        private var selectedID: Binding<String?>
        private var expandedIDs: Binding<Set<String>>
        private let onExpand: (DirectoryTreeNode) -> Void
        private var isRestoringExpansion = false
        private var isRestoringSelection = false
        weak var outlineView: NSOutlineView?

        init(
            selectedID: Binding<String?>,
            expandedIDs: Binding<Set<String>>,
            onExpand: @escaping (DirectoryTreeNode) -> Void
        ) {
            self.selectedID = selectedID
            self.expandedIDs = expandedIDs
            self.onExpand = onExpand
        }

        func update(
            root: DirectoryTreeNode,
            selectedID: String?,
            expandedIDs: Set<String>,
            loadingNodeIDs: Set<String>,
            outlineView: NSOutlineView
        ) {
            if root != lastRoot {
                let previousExpanded = currentExpandedIDs(in: outlineView)
                self.rootItem = TreeOutlineItem(node: root)
                self.itemsByID = rootItem?.indexedByID() ?? [:]
                self.lastRoot = root
                self.loadingNodeIDs = loadingNodeIDs

                let effectiveExpanded = expandedIDs.union(previousExpanded)
                outlineView.reloadData()
                restoreExpanded(effectiveExpanded, in: outlineView)
            } else if loadingNodeIDs != self.loadingNodeIDs {
                let changedIDs = loadingNodeIDs.symmetricDifference(self.loadingNodeIDs)
                self.loadingNodeIDs = loadingNodeIDs
                reloadRows(withIDs: changedIDs, in: outlineView)
            }

            restoreSelection(selectedID ?? root.id, in: outlineView)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            numberOfChildrenOfItem item: Any?
        ) -> Int {
            guard let item = item as? TreeOutlineItem else {
                return rootItem == nil ? 0 : 1
            }
            return item.children.count
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            child index: Int,
            ofItem item: Any?
        ) -> Any {
            guard let item = item as? TreeOutlineItem else {
                return rootItem as Any
            }
            return item.children[index]
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            isItemExpandable item: Any
        ) -> Bool {
            guard let item = item as? TreeOutlineItem else { return false }
            return item.node.isDirectory && !item.node.isTruncated
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? TreeOutlineItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("TreeOutlineCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? TreeOutlineCellView
                ?? TreeOutlineCellView(identifier: identifier)
            cell.configure(node: item.node, isLoading: loadingNodeIDs.contains(item.node.id))
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRestoringSelection, let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let item = outlineView.item(atRow: row) as? TreeOutlineItem else { return }
            selectedID.wrappedValue = item.node.id
            if item.node.isDirectory, !outlineView.isItemExpanded(item) {
                outlineView.expandItem(item)
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let item = notification.userInfo?["NSObject"] as? TreeOutlineItem else { return }
            expandedIDs.wrappedValue.insert(item.node.id)
            if item.node.children.isEmpty {
                onExpand(item.node)
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isRestoringExpansion,
                  let item = notification.userInfo?["NSObject"] as? TreeOutlineItem else { return }
            expandedIDs.wrappedValue.remove(item.node.id)
        }

        private func restoreExpanded(_ ids: Set<String>, in outlineView: NSOutlineView) {
            isRestoringExpansion = true
            defer { isRestoringExpansion = false }

            for id in ids {
                guard let item = itemsByID[id], item.node.isDirectory else { continue }
                outlineView.expandItem(item)
            }
            expandedIDs.wrappedValue = ids.intersection(Set(itemsByID.keys))
        }

        private func restoreSelection(_ id: String, in outlineView: NSOutlineView) {
            guard let item = itemsByID[id] else { return }
            let row = outlineView.row(forItem: item)
            guard row >= 0 else { return }
            if outlineView.selectedRow == row { return }

            isRestoringSelection = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            isRestoringSelection = false
        }

        private func currentExpandedIDs(in outlineView: NSOutlineView) -> Set<String> {
            guard outlineView.numberOfRows > 0 else { return [] }
            var ids = Set<String>()
            for row in 0..<outlineView.numberOfRows {
                guard let item = outlineView.item(atRow: row) as? TreeOutlineItem,
                      outlineView.isItemExpanded(item) else { continue }
                ids.insert(item.node.id)
            }
            return ids
        }

        private func reloadRows(withIDs ids: Set<String>, in outlineView: NSOutlineView) {
            let rows = ids.compactMap { id -> Int? in
                guard let item = itemsByID[id] else { return nil }
                let row = outlineView.row(forItem: item)
                return row >= 0 ? row : nil
            }
            guard !rows.isEmpty else { return }
            outlineView.reloadData(
                forRowIndexes: IndexSet(rows),
                columnIndexes: IndexSet(integer: 0)
            )
        }
    }
}

private final class TreeOutlineItem: NSObject {
    let node: DirectoryTreeNode
    let children: [TreeOutlineItem]

    init(node: DirectoryTreeNode) {
        self.node = node
        self.children = node.children.map(TreeOutlineItem.init)
    }

    func indexedByID() -> [String: TreeOutlineItem] {
        var result: [String: TreeOutlineItem] = [:]
        appendIndex(to: &result)
        return result
    }

    private func appendIndex(to result: inout [String: TreeOutlineItem]) {
        result[node.id] = self
        for child in children {
            child.appendIndex(to: &result)
        }
    }
}

private final class TreeOutlineCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(node: DirectoryTreeNode, isLoading: Bool) {
        imageView = iconView
        textField = titleField

        iconView.image = NSImage(systemSymbolName: node.kind.iconName, accessibilityDescription: nil)
        iconView.contentTintColor = NSColor(depth: node.depth)
        titleField.stringValue = node.name
        countField.stringValue = node.isDirectory ? TreeFormatter.count(node.childCount) : ""
        countField.isHidden = !node.isDirectory || isLoading

        spinner.isHidden = !isLoading
        if isLoading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleField.font = .systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.translatesAutoresizingMaskIntoConstraints = false

        countField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countField.textColor = .secondaryLabelColor
        countField.alignment = .right
        countField.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)
        addSubview(countField)
        addSubview(spinner)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: countField.leadingAnchor, constant: -8),

            countField.centerYAnchor.constraint(equalTo: centerYAnchor),
            countField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countField.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14)
        ])
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let treeOutlineColumn = NSUserInterfaceItemIdentifier("TreeOutlineColumn")
}

private extension NSColor {
    convenience init(depth: Int) {
        let colors: [NSColor] = [
            NSColor(red: 0.30, green: 0.72, blue: 1.0, alpha: 1.0),
            NSColor(red: 0.28, green: 0.86, blue: 0.54, alpha: 1.0),
            NSColor(red: 0.93, green: 0.63, blue: 0.24, alpha: 1.0),
            NSColor(red: 0.82, green: 0.40, blue: 0.96, alpha: 1.0),
            NSColor(red: 1.00, green: 0.35, blue: 0.50, alpha: 1.0),
            NSColor(red: 0.42, green: 0.48, blue: 1.00, alpha: 1.0)
        ]
        self.init(cgColor: colors[depth % colors.count].cgColor)!
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
            HStack(spacing: 10) {
                TreePanelTitle(title: "Tree Text", systemImage: "text.alignleft")

                Spacer()

                Text("\(TreeFormatter.count(lineCount)) lines")
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(sourceTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TreePalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 90, alignment: .trailing)

                TreeCompactStepper(
                    title: "Level",
                    value: $model.options.textDepth,
                    range: 1...12
                ) {
                    model.reloadTreeText()
                }

                Button {
                    model.copyTreeText(displayText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .rckGlassButton()
                .controlSize(.small)
                .fixedSize()
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
                InspectorLine(title: "Children", value: TreeFormatter.detailCount(node.childCount))
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
