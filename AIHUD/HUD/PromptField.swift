import AppKit
import SwiftUI

enum PromptSettings {
    static let multilineKey = "hud.multilinePrompt"

    static func loadMultiline(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: multilineKey)
    }

    static func saveMultiline(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: multilineKey)
    }
}

enum PromptLayout {
    static let maxVisibleLines = 10
    static let fontSize: CGFloat = 16

    static func font() -> NSFont {
        .systemFont(ofSize: fontSize)
    }

    static func lineHeight(for font: NSFont) -> CGFloat {
        max(
            ceil(NSLayoutManager().defaultLineHeight(for: font)),
            ceil(font.boundingRectForFont.height)
        )
    }

    static func fieldHeight(visibleLines: Int, font: NSFont) -> CGFloat {
        let lines = min(max(visibleLines, 1), maxVisibleLines)
        return lineHeight(for: font) * CGFloat(lines)
    }

    static func rowHeight(visibleLines: Int, font: NSFont) -> CGFloat {
        let extra = max(0, min(visibleLines, maxVisibleLines) - 1)
        return HUDMetrics.rowHeight + CGFloat(extra) * lineHeight(for: font)
    }

    static func verticalInset(font: NSFont) -> CGFloat {
        max(0, (HUDMetrics.rowHeight - lineHeight(for: font)) / 2)
    }

    static func paragraphStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let line = lineHeight(for: font)
        style.minimumLineHeight = line
        style.maximumLineHeight = line
        style.lineBreakMode = .byWordWrapping
        return style
    }

    static func typingAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle(for: font)
        ]
    }
}

@MainActor
protocol PromptEditing: AnyObject {
    func applyPrompt(_ text: String)
    var promptFocusView: NSView { get }
}

struct PromptField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var multiline: Bool
    var onSubmit: () -> Void
    var onReady: (any PromptEditing) -> Void
    var onHeight: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onHeight: onHeight)
    }

    func makeNSView(context: Context) -> PromptHostView {
        let host = PromptHostView()
        host.delegate = context.coordinator
        context.coordinator.host = host
        onReady(host)
        return host
    }

    func updateNSView(_ nsView: PromptHostView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHeight = onHeight
        nsView.delegate = context.coordinator
        nsView.placeholder = placeholder
        nsView.isMultiline = multiline
        nsView.applyPrompt(text)
        context.coordinator.publishHeight()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptHostView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        return CGSize(width: width, height: nsView.preferredHeight(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, PromptHostDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onHeight: (CGFloat) -> Void
        weak var host: PromptHostView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onHeight: @escaping (CGFloat) -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onHeight = onHeight
        }

        func promptHostTextDidChange(_ string: String) {
            if text.wrappedValue != string {
                text.wrappedValue = string
            }
            publishHeight()
        }

        func promptHostDidSubmit() {
            onSubmit()
        }

        func publishHeight() {
            guard let host else { return }
            let width = host.bounds.width > 1 ? host.bounds.width : 400
            onHeight(host.preferredHeight(forWidth: width))
        }
    }
}

@MainActor
protocol PromptHostDelegate: AnyObject {
    func promptHostTextDidChange(_ string: String)
    func promptHostDidSubmit()
}

final class PromptHostView: NSView, PromptEditing {
    let field = ClickThroughTextField(string: "")
    let scroll = ClickThroughScrollView()
    let textView = PromptTextView()
    weak var delegate: PromptHostDelegate?
    private var installed = false

    var placeholder: String = "Ask anything..." {
        didSet { applyPlaceholder() }
    }

    var isMultiline = false {
        didSet {
            guard oldValue != isMultiline else { return }
            syncEditorText(from: oldValue)
            mountEditor()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureField()
        configureMultiline()
        mountEditor()
    }

    required init?(coder: NSCoder) { return nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(promptFocusView) ?? false
    }

    func applyPrompt(_ text: String) {
        if isMultiline {
            textView.applyPrompt(text)
        } else {
            field.applyPrompt(text)
        }
    }

    var promptFocusView: NSView {
        isMultiline ? textView : field
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        if !isMultiline {
            return HUDMetrics.rowHeight
        }
        return PromptLayout.rowHeight(visibleLines: visibleLineCount(width: width), font: PromptLayout.font())
    }

    override func layout() {
        super.layout()
        field.frame = bounds
        if isMultiline {
            let inset = PromptLayout.verticalInset(font: PromptLayout.font())
            let height = max(0, bounds.height - inset * 2)
            scroll.frame = NSRect(x: 0, y: inset, width: bounds.width, height: height)
            let width = max(scroll.contentSize.width, bounds.width)
            textView.minSize = NSSize(width: width, height: 0)
            textView.frame.size.width = width
        } else {
            scroll.frame = bounds
        }
    }

    private func configureField() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.font = PromptLayout.font()
        field.textColor = .labelColor
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        if let cell = field.cell as? NSTextFieldCell {
            cell.isBordered = false
            cell.isBezeled = false
            cell.drawsBackground = false
            cell.wraps = false
            cell.isScrollable = true
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byClipping
        }
        field.delegate = field
        field.onChange = { [weak self] string in
            self?.delegate?.promptHostTextDidChange(string)
        }
        field.onSubmit = { [weak self] in
            self?.delegate?.promptHostDidSubmit()
        }
    }

    private func configureMultiline() {
        let font = PromptLayout.font()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = textView

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.defaultParagraphStyle = PromptLayout.paragraphStyle(for: font)
        textView.typingAttributes = PromptLayout.typingAttributes(font: font)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = textView
        textView.onChange = { [weak self] string in
            self?.delegate?.promptHostTextDidChange(string)
        }
        textView.onSubmit = { [weak self] in
            self?.delegate?.promptHostDidSubmit()
        }
    }

    private func mountEditor() {
        if !installed {
            addSubview(field)
            addSubview(scroll)
            installed = true
        }
        field.isHidden = isMultiline
        scroll.isHidden = !isMultiline
        applyPlaceholder()
        needsLayout = true
    }

    private func syncEditorText(from wasMultiline: Bool) {
        let current = wasMultiline ? textView.string : field.stringValue
        if isMultiline {
            textView.applyPrompt(current)
        } else {
            field.applyPrompt(current.replacingOccurrences(of: "\n", with: " "))
        }
    }

    private func applyPlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: PromptLayout.font()
            ]
        )
        textView.placeholder = placeholder
    }

    private func visibleLineCount(width: CGFloat) -> Int {
        let text = textView.string
        if text.isEmpty { return 1 }
        guard let container = textView.textContainer, let layout = textView.layoutManager else {
            return 1
        }
        let usable = max(width, 10)
        container.containerSize = NSSize(width: usable, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        var index = 0
        var lines = 0
        var lineRange = NSRange()
        let glyphs = layout.numberOfGlyphs
        while index < glyphs {
            layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
            index = NSMaxRange(lineRange)
            lines += 1
        }
        if text.hasSuffix("\n") {
            lines += 1
        }
        return min(max(lines, 1), PromptLayout.maxVisibleLines)
    }
}

final class CenteredPromptCell: NSTextFieldCell {
    override init(textCell string: String) {
        super.init(textCell: string)
        wraps = false
        isScrollable = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        wraps = false
        isScrollable = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTitleRect(for: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTitleRect(for: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: centeredTitleRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredTitleRect(for: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func centeredTitleRect(for rect: NSRect) -> NSRect {
        let title = super.drawingRect(forBounds: rect)
        let line = PromptLayout.lineHeight(for: font ?? PromptLayout.font())
        let height = min(line, title.height)
        let dy = max(0, (title.height - height) / 2)
        return NSRect(x: title.origin.x, y: title.origin.y + dy, width: title.width, height: height)
    }
}

final class ClickThroughTextField: NSTextField, NSTextFieldDelegate, PromptEditing {
    var onChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}

    override class var cellClass: AnyClass? {
        get { CenteredPromptCell.self }
        set {}
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func applyPrompt(_ text: String) {
        if stringValue != text {
            stringValue = text
        }
        guard let editor = currentEditor() else { return }
        if editor.string != text {
            editor.string = text
            let end = (text as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
        lockSingleLineEditor()
    }

    var promptFocusView: NSView { self }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        lockSingleLineEditor()
        return accepted
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        lockSingleLineEditor()
    }

    func controlTextDidChange(_ notification: Notification) {
        lockSingleLineEditor()
        onChange(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            if NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            onSubmit()
            return true
        }
        return false
    }

    private func lockSingleLineEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.textContainer?.widthTracksTextView = false
        let line = PromptLayout.lineHeight(for: font ?? PromptLayout.font())
        editor.textContainer?.containerSize = NSSize(width: 1_000_000, height: line)
        editor.textContainer?.lineBreakMode = .byClipping
        editor.isHorizontallyResizable = true
        editor.maxSize = NSSize(width: 1_000_000, height: line)
    }
}

final class ClickThroughScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PromptTextView: NSTextView, NSTextViewDelegate, PromptEditing {
    var placeholder = "Ask anything..." {
        didSet { needsDisplay = true }
    }
    var onChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    private var applyingAttributes = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func applyPrompt(_ text: String) {
        if string != text {
            let font = self.font ?? PromptLayout.font()
            textStorage?.setAttributedString(NSAttributedString(string: text, attributes: PromptLayout.typingAttributes(font: font)))
            let end = (text as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))
        }
        needsDisplay = true
    }

    var promptFocusView: NSView { self }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let font = self.font ?? PromptLayout.font()
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font
        ]
        let label = placeholder as NSString
        let size = label.size(withAttributes: attrs)
        let padding = textContainer?.lineFragmentPadding ?? 5
        let y = max(0, (PromptLayout.lineHeight(for: font) - size.height) / 2)
        label.draw(at: NSPoint(x: textContainerInset.width + padding, y: y), withAttributes: attrs)
    }

    override func didChangeText() {
        super.didChangeText()
        if !applyingAttributes {
            applyingAttributes = true
            enforcePromptAttributes()
            applyingAttributes = false
        }
        needsDisplay = true
        onChange(string)
    }

    private func enforcePromptAttributes() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let font = self.font ?? PromptLayout.font()
        storage.addAttributes(PromptLayout.typingAttributes(font: font), range: NSRange(location: 0, length: storage.length))
        typingAttributes = PromptLayout.typingAttributes(font: font)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            onSubmit()
            return true
        }
        return false
    }
}
