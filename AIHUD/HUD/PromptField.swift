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

    /// Computed once: building a layout manager each animation frame adds up.
    static let promptLineHeight = lineHeight(for: font())

    static func lineHeight(for font: NSFont) -> CGFloat {
        max(
            ceil(NSLayoutManager().defaultLineHeight(for: font)),
            ceil(font.boundingRectForFont.height)
        )
    }

    static func rowHeight(visibleLines: Int, font: NSFont) -> CGFloat {
        let extra = max(0, min(visibleLines, maxVisibleLines) - 1)
        return HUDMetrics.rowHeight + CGFloat(extra) * lineHeight(for: font)
    }

    static func verticalInset(font: NSFont) -> CGFloat {
        max(0, (HUDMetrics.rowHeight - lineHeight(for: font)) / 2)
    }

    /// NSTextContainer's default fragment padding. The multiline editor sets this explicitly.
    static let multilineFragmentPadding: CGFloat = 5
    static let multilineTextContainerInset = NSSize.zero

    /// Vertically centers one line inside the text field cell's drawing rect.
    static func singleLineGlyphRect(cellRect: NSRect, font: NSFont) -> NSRect {
        let line = lineHeight(for: font)
        let height = min(line, cellRect.height)
        let dy = max(0, (cellRect.height - height) / 2)
        return NSRect(x: cellRect.origin.x, y: cellRect.origin.y + dy, width: cellRect.width, height: height)
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

enum PromptShortcut {
    static func handle(
        event: NSEvent?,
        multiline: Bool,
        insertNewline: () -> Void,
        submit: () -> Void
    ) -> Bool {
        guard let event else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch HUDShortcuts.action(
            keyCode: event.keyCode,
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            panelIsKey: true,
            menuTracking: false,
            hasAttachedSheet: false,
            bindings: CardShortcutBindings.current()
        ) {
        case .newline:
            if multiline { insertNewline() }
            return true
        case .send:
            submit()
            return true
        default:
            return false
        }
    }
}

@MainActor
protocol PromptEditing: AnyObject {
    func applyPrompt(_ text: String)
    func insertLineBreak()
    var promptFocusView: NSView { get }
}

extension PromptEditing {
    func insertLineBreak() {}
}

struct PromptField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var multiline: Bool
    var isEditable: Bool = true
    var showsInFlightShimmer: Bool = false
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
        context.coordinator.isEditable = isEditable
        nsView.delegate = context.coordinator
        nsView.placeholder = placeholder
        nsView.isMultiline = multiline
        nsView.isPromptEditable = isEditable
        nsView.showsInFlightShimmer = showsInFlightShimmer
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
        var isEditable = true
        weak var host: PromptHostView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onHeight: @escaping (CGFloat) -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onHeight = onHeight
        }

        func promptHostTextDidChange(_ string: String) {
            guard isEditable else { return }
            if text.wrappedValue != string {
                text.wrappedValue = string
            }
            publishHeight()
        }

        func promptHostDidSubmit() {
            guard isEditable else { return }
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

    var placeholder: String = String(localized: "Ask anything...") {
        didSet { applyPlaceholder() }
    }

    var isMultiline = false {
        didSet {
            guard oldValue != isMultiline else { return }
            syncEditorText(from: oldValue)
            mountEditor()
        }
    }

    var isPromptEditable = true {
        didSet {
            guard oldValue != isPromptEditable else { return }
            applyEditableState()
        }
    }

    var showsInFlightShimmer = false {
        didSet {
            guard oldValue != showsInFlightShimmer else { return }
            field.showsInFlightShimmer = showsInFlightShimmer
            textView.showsInFlightShimmer = showsInFlightShimmer
            if showsInFlightShimmer {
                startShimmerClock()
            } else {
                stopShimmerClock()
            }
        }
    }

    private var shimmerClock: PromptShimmerClock?
    private var shimmerTimer: Timer?

    func redrawInFlightShimmer() {
        field.needsDisplay = true
        textView.needsDisplay = true
    }

    private func startShimmerClock() {
        guard shimmerTimer == nil else { return }
        let clock = shimmerClock ?? PromptShimmerClock()
        clock.host = self
        shimmerClock = clock
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: clock,
            selector: #selector(PromptShimmerClock.tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        shimmerTimer = timer
    }

    private func stopShimmerClock() {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
        field.needsDisplay = true
        textView.needsDisplay = true
    }

    deinit {
        MainActor.assumeIsolated {
            shimmerTimer?.invalidate()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureField()
        configureMultiline()
        mountEditor()
        applyEditableState()
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

    func insertLineBreak() {
        guard isMultiline else { return }
        textView.insertNewlineIgnoringFieldEditor(nil)
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
        textView.textContainerInset = PromptLayout.multilineTextContainerInset
        textView.textContainer?.lineFragmentPadding = PromptLayout.multilineFragmentPadding
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
        applyEditableState()
        needsLayout = true
    }

    private func applyEditableState() {
        field.isEditable = isPromptEditable
        field.isSelectable = isPromptEditable
        textView.isEditable = isPromptEditable
        textView.isSelectable = isPromptEditable
        if !isPromptEditable {
            window?.makeFirstResponder(nil)
        }
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

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let field = controlView as? ClickThroughTextField,
              field.showsInFlightShimmer,
              !stringValue.isEmpty
        else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        let saved = textColor
        textColor = NSColor.white.withAlphaComponent(0.38)
        super.drawInterior(withFrame: cellFrame, in: controlView)
        textColor = .white
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            super.drawInterior(withFrame: cellFrame, in: controlView)
            context.setBlendMode(.sourceIn)
            PromptShimmerBand.draw(in: titleRect(forBounds: cellFrame))
            context.endTransparencyLayer()
            context.restoreGState()
        }
        textColor = saved
    }

    private func centeredTitleRect(for rect: NSRect) -> NSRect {
        PromptLayout.singleLineGlyphRect(
            cellRect: super.drawingRect(forBounds: rect),
            font: font ?? PromptLayout.font()
        )
    }
}

final class ClickThroughTextField: NSTextField, NSTextFieldDelegate, PromptEditing {
    var onChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var showsInFlightShimmer = false {
        didSet { needsDisplay = true }
    }

    override class var cellClass: AnyClass? {
        get { CenteredPromptCell.self }
        set {}
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func applyPrompt(_ text: String) {
        var replaced = false
        if stringValue != text {
            stringValue = text
            replaced = true
        }
        guard let editor = currentEditor() else { return }
        if editor.string != text {
            editor.string = text
            replaced = true
        }
        // Replacing the text of a focused field selects all of it, so put the caret at the end. The same text
        // (pushed back on every SwiftUI update) leaves the caret where the user put it.
        if replaced {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        lockSingleLineEditor()
    }

    var promptFocusView: NSView { self }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // AppKit selects all text on focus, so the next key would replace a restored draft. Caret to the end.
        if let editor = currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
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
            return PromptShortcut.handle(
                event: NSApp.currentEvent,
                multiline: false,
                insertNewline: { textView.insertNewlineIgnoringFieldEditor(nil) },
                submit: onSubmit
            )
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
    var placeholder = String(localized: "Ask anything...") {
        didSet { needsDisplay = true }
    }
    var onChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var showsInFlightShimmer = false {
        didSet { needsDisplay = true }
    }
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
        if showsInFlightShimmer, !string.isEmpty {
            drawInFlightShimmer()
            return
        }
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

    private func drawInFlightShimmer() {
        guard let layout = layoutManager, let container = textContainer else { return }
        let glyphRange = layout.glyphRange(for: container)
        guard glyphRange.length > 0 else { return }
        let characters = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let origin = textContainerOrigin
        let dim = NSColor.white.withAlphaComponent(0.38)
        layout.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: characters)
        layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: characters)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        layout.addTemporaryAttribute(.foregroundColor, value: NSColor.white, forCharacterRange: characters)
        layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: characters)
        context.setBlendMode(.sourceIn)
        PromptShimmerBand.draw(in: bounds)
        context.endTransparencyLayer()
        context.restoreGState()
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
            return PromptShortcut.handle(
                event: NSApp.currentEvent,
                multiline: true,
                insertNewline: { textView.insertNewlineIgnoringFieldEditor(nil) },
                submit: onSubmit
            )
        }
        return false
    }
}

private final class PromptShimmerClock: NSObject {
    weak var host: PromptHostView?

    @objc func tick() {
        host?.redrawInFlightShimmer()
    }
}

enum PromptShimmerBand {
    static func draw(in rect: NSRect) {
        let width = max(rect.width, 1)
        let band = max(width * 0.42, 36)
        let phase = InFlightPromptShimmer.bandPhase(at: Date(), duration: InFlightPromptShimmer.bandDuration)
        let x = rect.minX - band + phase * (width + band)
        let bandRect = NSRect(x: x, y: rect.minY, width: band, height: rect.height)
        guard let gradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0),
            NSColor.white,
            NSColor.white.withAlphaComponent(0),
        ]) else { return }
        gradient.draw(in: bandRect, angle: 0)
    }
}
