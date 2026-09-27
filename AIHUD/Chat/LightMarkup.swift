import Foundation

enum TextRun: Equatable, Sendable {
    case plain(String)
    case bold(String)
    case bullet(String)
    case numbered(Int, String)
}

enum LightMarkup {
    static func parse(_ source: String) -> [TextRun] {
        var runs: [TextRun] = []
        var paragraphCount = 0
        for lineSub in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSub)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if let numbered = numberedLine(line) {
                runs.append(.numbered(numbered.0, numbered.1))
                continue
            }
            if let bullet = bulletLine(line) {
                runs.append(.bullet(bullet))
                continue
            }
            var inline = inlineRuns(line)
            if paragraphCount > 0 {
                if case .plain(let text) = inline.first {
                    inline[0] = .plain("\n" + text)
                } else {
                    inline.insert(.plain("\n"), at: 0)
                }
            }
            runs.append(contentsOf: inline)
            paragraphCount += 1
        }
        return runs
    }

    private static func numberedLine(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: "."), dot > line.startIndex else { return nil }
        let prefix = line[..<dot]
        guard let number = Int(prefix), line[dot...].hasPrefix(". ") else { return nil }
        let body = line[line.index(dot, offsetBy: 2)...]
        return (number, String(body))
    }

    private static func bulletLine(_ line: String) -> String? {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        return nil
    }

    private static func inlineRuns(_ line: String) -> [TextRun] {
        var runs: [TextRun] = []
        var rest = line[...]
        while let start = rest.range(of: "**") {
            let before = rest[..<start.lowerBound]
            if !before.isEmpty {
                runs.append(.plain(String(before)))
            }
            let after = rest[start.upperBound...]
            guard let end = after.range(of: "**") else {
                runs.append(.plain(String(rest[start.lowerBound...])))
                return runs
            }
            runs.append(.bold(String(after[..<end.lowerBound])))
            rest = after[end.upperBound...]
        }
        if !rest.isEmpty {
            runs.append(.plain(String(rest)))
        }
        if runs.isEmpty {
            runs.append(.plain(line))
        }
        return runs
    }
}
