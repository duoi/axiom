import AppKit
import Foundation

enum ReplyMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        var result = AttributedString()
        for segment in segments(in: source) {
            let piece: AttributedString
            switch segment {
            case .markdown(let text):
                piece = parseMarkdown(text)
            case .code(let language, let body):
                piece = codeBlock(language: language, body: body)
            case .plain(let text):
                piece = AttributedString(text)
            }
            if !result.characters.isEmpty && !piece.characters.isEmpty {
                result += AttributedString("\n")
            }
            result += piece
        }
        return result
    }

    static func containsInline(_ text: AttributedString, _ intent: InlinePresentationIntent) -> Bool {
        text.runs.contains { $0.inlinePresentationIntent?.contains(intent) == true }
    }

    static func containsCodeBlock(_ text: AttributedString) -> Bool {
        text.runs.contains { run in
            guard let intent = run.presentationIntent else { return false }
            return intent.components.contains { component in
                if case .codeBlock = component.kind { return true }
                return false
            }
        }
    }

    static func containsLink(_ text: AttributedString) -> Bool {
        text.runs.contains { $0.link != nil }
    }

    private enum Segment {
        case markdown(String)
        case code(language: String, body: String)
        case plain(String)
    }

    private static func segments(in source: String) -> [Segment] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [Segment] = []
        var markdownLines: [String] = []
        var index = 0

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            let text = markdownLines.joined(separator: "\n")
            markdownLines = []
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            result.append(.markdown(text))
        }

        while index < lines.count {
            if let open = fence(lines[index]) {
                let start = index
                index += 1
                var body: [String] = []
                var closed = false
                while index < lines.count {
                    if let close = fence(lines[index]),
                       close.char == open.char,
                       close.len >= open.len,
                       close.info.isEmpty
                    {
                        closed = true
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                if closed {
                    flushMarkdown()
                    result.append(.code(language: open.info, body: body.joined(separator: "\n")))
                } else {
                    flushMarkdown()
                    result.append(.plain(lines[start...].joined(separator: "\n")))
                    return result
                }
            } else {
                markdownLines.append(lines[index])
                index += 1
            }
        }
        flushMarkdown()
        return result
    }

    private struct Fence {
        var char: Character
        var len: Int
        var info: String
    }

    private static func fence(_ line: String) -> Fence? {
        var cursor = line.startIndex
        var indent = 0
        while cursor < line.endIndex, line[cursor] == " ", indent < 3 {
            indent += 1
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }
        let char = line[cursor]
        guard char == "`" || char == "~" else { return nil }
        var len = 0
        while cursor < line.endIndex, line[cursor] == char {
            len += 1
            cursor = line.index(after: cursor)
        }
        guard len >= 3 else { return nil }
        let info = String(line[cursor...]).trimmingCharacters(in: .whitespaces)
        if char == "`", info.contains("`") { return nil }
        return Fence(char: char, len: len, info: info)
    }

    private static func parseMarkdown(_ source: String) -> AttributedString {
        var result = AttributedString()
        for lineSub in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSub)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if !result.characters.isEmpty {
                result += AttributedString("\n")
            }
            if let heading = headingLine(trimmed) {
                var piece = inlineMarkdown(heading.text)
                let size: CGFloat = heading.level <= 1 ? 17 : heading.level == 2 ? 15 : 13
                piece.font = NSFont.systemFont(ofSize: size, weight: .semibold)
                result += piece
                continue
            }
            if let item = listLine(trimmed) {
                result += AttributedString(item.marker)
                result += inlineMarkdown(item.text)
                continue
            }
            result += inlineMarkdown(trimmed)
        }
        return result
    }

    private static func headingLine(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while level < 6, index < line.endIndex, line[index] == "#" {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        return (level, String(line[line.index(after: index)...]))
    }

    private static func listLine(_ line: String) -> (marker: String, text: String)? {
        if line.hasPrefix("- ") { return ("• ", String(line.dropFirst(2))) }
        if line.hasPrefix("* ") { return ("• ", String(line.dropFirst(2))) }
        guard let dot = line.firstIndex(of: "."), dot > line.startIndex else { return nil }
        let prefix = line[..<dot]
        guard let number = Int(prefix), line[dot...].hasPrefix(". ") else { return nil }
        return ("\(number). ", String(line[line.index(dot, offsetBy: 2)...]))
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let parsed = try? AttributedString(markdown: source, options: options) {
            return style(parsed)
        }
        return AttributedString(source)
    }

    private static func style(_ source: AttributedString) -> AttributedString {
        var text = source
        for run in text.runs {
            if run.link != nil {
                text[run.range].link = nil
                text[run.range].underlineStyle = .single
                text[run.range].foregroundColor = NSColor.secondaryLabelColor
            }
            if let intent = run.presentationIntent {
                for component in intent.components {
                    switch component.kind {
                    case .header(let level):
                        let size: CGFloat = level <= 1 ? 17 : (level == 2 ? 15 : 13)
                        text[run.range].font = NSFont.systemFont(ofSize: size, weight: .semibold)
                        text[run.range].foregroundColor = NSColor.labelColor
                    case .codeBlock:
                        text[run.range].font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                        text[run.range].foregroundColor = NSColor.labelColor
                    default:
                        break
                    }
                }
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                text[run.range].font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            }
        }
        return text
    }

    private static func codeBlock(language: String, body: String) -> AttributedString {
        var result = AttributedString()
        if !language.isEmpty {
            var label = AttributedString(language)
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.foregroundColor = NSColor.secondaryLabelColor
            result += label
            result += AttributedString("\n")
        }
        var code = AttributedString(body)
        code.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        code.foregroundColor = NSColor.labelColor
        code.presentationIntent = PresentationIntent(.codeBlock(languageHint: language.isEmpty ? nil : language), identity: 1)
        result += code
        return result
    }
}
