import AppKit
import SwiftUI

enum HighlightLanguage {
    case shell
    case yaml
    case plain
}

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var language: HighlightLanguage
    var isReadOnly = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = !isReadOnly
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.language = language
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = !isReadOnly
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        if textView.string != text {
            context.coordinator.apply(text)
        } else {
            context.coordinator.highlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var language: HighlightLanguage
        private var isApplying = false

        init(text: Binding<String>, language: HighlightLanguage) {
            self._text = text
            self.language = language
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            text = textView.string
            highlightPreservingSelection()
        }

        func apply(_ value: String) {
            guard let textView else { return }
            isApplying = true
            textView.string = value
            highlight()
            isApplying = false
        }

        func highlightPreservingSelection() {
            guard let textView else { return }
            let selectedRanges = textView.selectedRanges
            highlight()
            textView.selectedRanges = selectedRanges
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            switch language {
            case .shell:
                applyShellHighlighting(storage)
            case .yaml:
                applyYAMLHighlighting(storage)
            case .plain:
                break
            }

            storage.endEditing()
        }

        private func applyShellHighlighting(_ storage: NSTextStorage) {
            color(storage, pattern: #"(?m)#.*$"#, color: .secondaryLabelColor)
            color(storage, pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemGreen)
            color(storage, pattern: #"\b(if|then|else|elif|fi|for|in|do|done|while|case|esac|function|exec|exit|set|cd|eval|echo|printf|open)\b"#, color: .systemPurple)
            color(storage, pattern: #"\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\}"#, color: .systemBlue)
            color(storage, pattern: #"\b[A-Z_][A-Z0-9_]*(?==)"#, color: .systemOrange)
        }

        private func applyYAMLHighlighting(_ storage: NSTextStorage) {
            color(storage, pattern: #"(?m)#.*$"#, color: .secondaryLabelColor)
            color(storage, pattern: #"(?m)^[A-Za-z0-9_-]+(?=\s*:)"#, color: .systemBlue)
            color(storage, pattern: #"\b(true|false)\b"#, color: .systemPurple)
            color(storage, pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemGreen)
        }

        private func color(_ storage: NSTextStorage, pattern: String, color: NSColor) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }
}
