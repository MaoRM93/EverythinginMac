import SwiftUI
import AppKit

// MARK: - Query Token Types for Syntax Highlighting

enum QueryTokenType {
    case filterName   // "ext:", "size:", etc.
    case filterArg    // the value after filter colon: "cpp", ">1mb"
    case quoted       // text inside double quotes (including the quotes)
    case op           // |, !, <, >
    case word         // plain search term
}

struct QueryToken {
    let range: NSRange
    let type: QueryTokenType
}

// MARK: - Swift-side Query Tokenizer (mirrors C++ QueryTokenizer logic)

enum QueryHighlightTokenizer {
    private static let knownFilters: Set<String> = [
        // Phase 2 filters
        "ext", "size", "file", "folder",
        "path", "nopath", "parent", "depth", "len",
        // Phase 3 date filters
        "dm", "dc", "da",
        "datemodified", "datecreated", "dateaccessed",
        // Phase 4 modifiers
        "case", "nocase", "regex", "ww", "wfn",
        "wholeword", "wholefilename",
        // Phase 4 macros
        "audio", "video", "pic", "doc", "exe", "zip",
        // Content
        "content",
        // Type shorthand
        "type",
    ]

    static func tokenize(_ input: String) -> [QueryToken] {
        let chars = Array(input.utf16)
        let len = chars.count
        var tokens: [QueryToken] = []
        var i = 0

        while i < len {
            let c = chars[i]

            // Skip whitespace
            if c == 0x20 || c == 0x09 { // space or tab
                i += 1
                continue
            }

            // Single-character operators
            if c == 0x7C || c == 0x21 { // | or !
                tokens.append(QueryToken(range: NSRange(location: i, length: 1), type: .op))
                i += 1
                continue
            }
            if c == 0x3C || c == 0x3E { // < or >
                tokens.append(QueryToken(range: NSRange(location: i, length: 1), type: .op))
                i += 1
                continue
            }

            // Quoted string
            if c == 0x22 { // "
                let start = i
                i += 1 // skip opening quote
                while i < len && chars[i] != 0x22 {
                    i += 1
                }
                if i < len { i += 1 } // skip closing quote
                tokens.append(QueryToken(range: NSRange(location: start, length: i - start), type: .quoted))
                continue
            }

            // Word or filter: collect until whitespace or operator
            let wordStart = i
            while i < len {
                let ch = chars[i]
                if ch == 0x20 || ch == 0x09 || ch == 0x7C || ch == 0x21
                    || ch == 0x3C || ch == 0x3E || ch == 0x22 {
                    break
                }
                i += 1
            }

            if i > wordStart {
                // Extract the word as a String for filter name checking
                let wordRange = NSRange(location: wordStart, length: i - wordStart)
                let word = (input as NSString).substring(with: wordRange)

                // Check for filter: name:value
                if let colonIdx = word.firstIndex(of: ":"), colonIdx > word.startIndex {
                    let name = String(word[word.startIndex..<colonIdx]).lowercased()

                    if knownFilters.contains(name) {
                        // It's a known filter.
                        // Filter name includes the colon
                        let nameLen = word.distance(from: word.startIndex, to: colonIdx) + 1 // +1 for colon
                        tokens.append(QueryToken(
                            range: NSRange(location: wordStart, length: nameLen),
                            type: .filterName
                        ))

                        // Re-collect the argument: for filters, < > are allowed in the arg
                        let argStartInInput = wordStart + nameLen
                        var argEnd = argStartInInput
                        while argEnd < len {
                            let ch = chars[argEnd]
                            if ch == 0x20 || ch == 0x09 || ch == 0x7C || ch == 0x21 || ch == 0x22 {
                                break
                            }
                            argEnd += 1
                        }
                        if argEnd > argStartInInput {
                            tokens.append(QueryToken(
                                range: NSRange(location: argStartInInput, length: argEnd - argStartInInput),
                                type: .filterArg
                            ))
                        }
                        i = argEnd
                        continue
                    }
                }

                // Not a filter — plain word
                tokens.append(QueryToken(range: wordRange, type: .word))
            }
        }

        return tokens
    }

    /// Extract only the search keywords (plain words + unquoted text from quoted strings)
    /// from a query, stripping out filter tokens and operators.
    /// e.g. "ext:cpp hello" → ["hello"], "ext:cpp \"hello world\"" → ["hello world"]
    static func extractSearchKeywords(_ input: String) -> [String] {
        let tokens = tokenize(input)
        var keywords: [String] = []
        for token in tokens {
            switch token.type {
            case .word:
                keywords.append((input as NSString).substring(with: token.range))
            case .quoted:
                var text = (input as NSString).substring(with: token.range)
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !text.isEmpty { keywords.append(text) }
            default: break
            }
        }
        return keywords
    }
}

// MARK: - HighlightedSearchField (NSViewRepresentable)

struct HighlightedSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var ghostSuggestion: String?
    var isFocused: FocusState<Bool>.Binding
    var isListFocused: Bool = false
    var onTab: ((Bool) -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onListKey: ((NSEvent) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SearchScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = HighlightedNSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        // Insets are computed in `layout()` so the single line stays optically
        // centred in the field, aligned with the magnifying glass icon.
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        textView.minSize = NSSize(width: 0, height: 24)
        textView.frame = NSRect(x: 0, y: 0, width: 10, height: 24)
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("searchField")

        // Single-line behavior: disable Enter/Return
        textView.isFieldEditor = true

        // Tab key handling
        textView.onTabKey = context.coordinator.handleTab
        textView.onDownArrowKey = context.coordinator.handleDownArrow
        textView.onListKey = context.coordinator.handleListKey

        // Escape key handling: clear query, then release focus
        textView.onEscapeKey = context.coordinator.handleEscape

        // Placeholder
        textView.placeholderString = placeholder

        // Keep the SwiftUI focus flag in sync when AppKit gives the text view
        // first responder on its own.
        textView.onFocusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.isFocused.wrappedValue = focused
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightedNSTextView else { return }

        // SwiftUI re-renders this view whenever an observed value changes (for
        // example index progress). While an input method is composing, any
        // responder/string/attribute mutation cancels the composition, which
        // shows up as a flashing candidate window. Leave the text view alone
        // until the composition is committed or cancelled.
        if textView.hasMarkedText() { return }

        // Never overwrite the text while an input method (Pinyin etc.) is
        // composing marked text — reassigning `string` cancels the composition.
        if textView.string != text {
            // Update text if externally changed (e.g., clear button, ghost suggestion accept)
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(textView)
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromSwiftUI = false
        }

        // Update ghost suggestion
        if textView.ghostSuggestion != ghostSuggestion {
            textView.ghostSuggestion = ghostSuggestion
        }

        // Caret follows the visual focus: hidden while the result list owns
        // the keyboard selection, visible while the search field is active.
        if textView.isListFocused != isListFocused {
            textView.isListFocused = isListFocused
        }

        context.coordinator.parent = self

        // Handle focus
        if isFocused.wrappedValue && textView.window != nil && textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedSearchField
        weak var textView: NSTextView?
        var isUpdatingFromSwiftUI = false

        init(_ parent: HighlightedSearchField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let textView = notification.object as? NSTextView else { return }

            // While marked text exists the input method owns the composition.
            // Re-applying attributes here cancels it, so wait for the commit.
            if textView.hasMarkedText() { return }

            parent.text = textView.string
            applyHighlighting(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Selection changes happen constantly during input-method
            // composition; publishing them would re-render the view and can
            // cancel the composition. Only sync when no marked text exists.
            if let textView = notification.object as? NSTextView, !textView.hasMarkedText() {
                let isFocused = textView.window?.firstResponder === textView
                if parent.isFocused.wrappedValue != isFocused {
                    parent.isFocused.wrappedValue = isFocused
                }
            }
        }

        func handleTab(shift: Bool) -> Bool {
            return parent.onTab?(shift) ?? false
        }

        func handleDownArrow() -> Bool {
            return parent.onDownArrow?() ?? false
        }

        func handleListKey(_ event: NSEvent) -> Bool {
            return parent.onListKey?(event) ?? false
        }

        func handleEscape() {
            guard let textView else { return }
            if textView.string.isEmpty {
                // Empty query: Escape hides the Spotlight-style window.
                textView.window?.orderOut(nil)
                parent.isFocused.wrappedValue = false
            } else {
                textView.string = ""
                parent.text = ""
                applyHighlighting(textView)
            }
        }

        func applyHighlighting(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let text = textStorage.string
            let font = NSFont.systemFont(ofSize: 17)

            // Reset to default style
            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ], range: fullRange)

            // Tokenize and apply colors
            let tokens = QueryHighlightTokenizer.tokenize(text)
            for token in tokens {
                guard token.range.location + token.range.length <= textStorage.length else { continue }

                let color: NSColor
                switch token.type {
                case .filterName:
                    color = .systemPurple
                case .filterArg:
                    color = .systemBlue
                case .quoted:
                    color = .systemOrange
                case .op:
                    color = .systemRed
                case .word:
                    continue // default color
                }

                textStorage.addAttribute(.foregroundColor, value: color, range: token.range)
            }

            textStorage.endEditing()
        }
    }
}

// MARK: - Single-line scroll container

/// Keeps the document view exactly as tall as the clip view so the text is
/// laid out from the top of a full-height field instead of being pinned to
/// the top edge of a shorter document view (which made the text sit higher
/// than the magnifying glass icon).
private final class SearchScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let target = NSSize(width: max(documentView.frame.width, contentSize.width),
                            height: contentSize.height)
        if documentView.frame.size != target {
            documentView.setFrameSize(target)
        }
    }
}

// MARK: - Custom NSTextView subclass for Tab key handling

class HighlightedNSTextView: NSTextView {
    var onTabKey: ((Bool) -> Bool)?
    var onDownArrowKey: (() -> Bool)?
    var onListKey: ((NSEvent) -> Bool)?
    var onEscapeKey: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var placeholderString: String = ""
    private var focusObservers: [NSObjectProtocol] = []

    var isListFocused: Bool = false {
        didSet {
            insertionPointColor = isListFocused ? .clear : .labelColor
            needsDisplay = true
        }
    }

    var ghostSuggestion: String? {
        didSet { needsDisplay = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        focusObservers.removeAll()

        guard let window else { return }

        // The search field is the primary control, so give it focus as soon as
        // the window becomes key (launch, hotkey summon, app re-activation).
        focusObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.focusIfPossible()
        })
        focusObservers.append(NotificationCenter.default.addObserver(
            forName: .focusSearchField, object: nil, queue: .main
        ) { [weak self] _ in
            self?.focusIfPossible()
        })

        if window.isKeyWindow {
            DispatchQueue.main.async { [weak self] in
                self?.focusIfPossible()
            }
        }
    }

    /// AppKit owns first responder here; SwiftUI's focus state alone cannot
    /// reliably move it into a view wrapped by `NSViewRepresentable`.
    private func focusIfPossible() {
        guard let window, window.isKeyWindow else { return }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        onFocusChanged?(window.firstResponder === self)
    }

    deinit {
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func layout() {
        super.layout()
        centerTextVertically()
    }

    /// A single-line NSTextView draws from the top inset, which made the text
    /// sit lower than the magnifying glass when the field height changed.
    /// Recompute the inset from the actual bounds so the placeholder, the
    /// typed text and the icon all share one optical centre line.
    private func centerTextVertically() {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 17))
        let inset = max(0, (bounds.height - lineHeight) / 2)
        if abs(textContainerInset.height - inset) > 0.25 {
            textContainerInset = NSSize(width: 0, height: inset)
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        // Let the input method finish/cancel its own composition first.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        // The search text view stays first responder while the result list
        // owns the keyboard selection, so navigation is handled here.
        if let listHandler = onListKey, listHandler(event) {
            return
        }

        // Tab moves focus to the result list (or back from it).
        if event.keyCode == 48 {
            if let handler = onTabKey, handler(event.modifierFlags.contains(.shift)) {
                return
            }
        }

        // Arrow down from the search field selects the first result.
        if event.keyCode == 125, let handler = onDownArrowKey, handler() {
            return
        }

        // Handle Escape: clear query, then hide the window.
        if event.keyCode == 53 {
            onEscapeKey?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw ghost suggestion behind the real text (before super.draw paints the typed text)
        if let ghost = ghostSuggestion, !ghost.isEmpty, !string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.4),
            ]
            let ghostStr = NSAttributedString(string: ghost, attributes: attrs)
            let inset = textContainerInset
            let origin = NSPoint(
                x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: inset.height
            )
            ghostStr.draw(at: origin)
        }

        super.draw(dirtyRect)

        // Draw placeholder when empty
        if string.isEmpty && !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
            let placeholder = NSAttributedString(string: placeholderString, attributes: attrs)
            let inset = textContainerInset
            let origin = NSPoint(
                x: inset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: inset.height
            )
            placeholder.draw(at: origin)
        }
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set { super.needsDisplay = newValue }
    }

    // Ensure placeholder redraws when text changes
    override var string: String {
        didSet {
            needsDisplay = true
        }
    }
}
