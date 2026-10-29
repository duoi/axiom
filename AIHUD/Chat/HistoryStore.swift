import Foundation
import Observation

enum HistorySettings {
    static let enabledKey = "history.enabled"
    static let saveScreenshotsKey = "history.saveScreenshots"

    static func loadEnabled(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func saveEnabled(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: enabledKey)
    }

    static func loadSaveScreenshots(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: saveScreenshotsKey)
    }

    static func saveSaveScreenshots(_ value: Bool, to defaults: UserDefaults) {
        defaults.set(value, forKey: saveScreenshotsKey)
    }
}

struct HistoryTurnRecord: Codable, Equatable, Sendable {
    var role: String
    var text: String
    /// Basenames of JPEG files under the history screenshots folder for this turn.
    var screenshotNames: [String]

    init(role: String, text: String, screenshotNames: [String] = []) {
        self.role = role
        self.text = text
        self.screenshotNames = screenshotNames
    }

    enum CodingKeys: String, CodingKey {
        case role
        case text
        case screenshotNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        screenshotNames = try container.decodeIfPresent([String].self, forKey: .screenshotNames) ?? []
    }
}

struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var savedAt: Date
    var turns: [HistoryTurnRecord]
    var contextFilenames: [String]
    var hasScreenshot: Bool

    /// Short title for the table: first user line.
    var title: String {
        let first = turns.first(where: { $0.role == "user" })?.text
            ?? turns.first?.text
            ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 72 { return trimmed }
        return String(trimmed.prefix(72)) + "…"
    }
}

enum HistoryPolicy {
    /// Turns written to disk. Includes a live `displayAnswer` when finish/stop never committed it
    /// (stream ended while still waiting/streaming), so a completed reply is not dropped.
    static func turnsForRecording(from session: Session) -> [Turn] {
        var turns = session.turns
        switch session.phase {
        case .waiting, .streaming:
            if !session.displayAnswer.isEmpty {
                let alreadyCommitted = turns.last?.role == .assistant
                    && turns.last?.text == session.displayAnswer
                if !alreadyCommitted {
                    turns.append(Turn(role: .assistant, text: session.displayAnswer, chips: []))
                }
            }
        case .composing, .finished, .failed:
            break
        }
        return turns
    }

    static func shouldRecord(
        historyEnabled: Bool,
        excludeFromHistory: Bool,
        turns: [Turn]
    ) -> Bool {
        guard historyEnabled, !excludeFromHistory else { return false }
        let hasUser = turns.contains { $0.role == .user }
        let hasAssistant = turns.contains { $0.role == .assistant && !$0.text.isEmpty }
        return hasUser && hasAssistant
    }

    static func shouldRecord(
        historyEnabled: Bool,
        excludeFromHistory: Bool,
        session: Session
    ) -> Bool {
        shouldRecord(
            historyEnabled: historyEnabled,
            excludeFromHistory: excludeFromHistory,
            turns: turnsForRecording(from: session)
        )
    }

    static func contextFilenames(from turns: [Turn]) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for turn in turns {
            for chip in turn.chips where !chip.isScreen {
                let name = Self.displayFilename(chip.name)
                guard !name.isEmpty, !seen.contains(name) else { continue }
                seen.insert(name)
                names.append(name)
            }
        }
        return names
    }

    static func displayFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).lastPathComponent
    }

    static func screenJPEGs(from turns: [Turn]) -> [(turnIndex: Int, data: Data)] {
        var result: [(turnIndex: Int, data: Data)] = []
        for (index, turn) in turns.enumerated() {
            for chip in turn.chips where chip.isScreen {
                if case .jpeg(let data) = chip.payload, !data.isEmpty {
                    result.append((index, data))
                }
            }
        }
        return result
    }
}

@Observable
final class HistoryStore {
    private let root: URL
    private let fileManager: FileManager
    private let indexURL: URL
    private let screenshotsURL: URL
    private let maxEntries: Int
    private(set) var entries: [HistoryEntry]

    init(root: URL, fileManager: FileManager = .default, maxEntries: Int = 500) {
        self.root = root
        self.fileManager = fileManager
        self.maxEntries = maxEntries
        self.indexURL = root.appendingPathComponent("history.json")
        self.screenshotsURL = root.appendingPathComponent("screenshots", isDirectory: true)
        self.entries = Self.loadEntries(from: indexURL, fileManager: fileManager)
    }

    static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let folder = base
            .appendingPathComponent("com.duoi.axiom", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    func record(
        session: Session,
        excludeFromHistory: Bool,
        historyEnabled: Bool,
        saveScreenshots: Bool
    ) -> HistoryEntry? {
        let turns = HistoryPolicy.turnsForRecording(from: session)
        guard HistoryPolicy.shouldRecord(
            historyEnabled: historyEnabled,
            excludeFromHistory: excludeFromHistory,
            turns: turns
        ) else {
            return nil
        }

        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let startedAt = session.startedAt ?? Date()
        let id = session.historyID
            ?? entries.first(where: { $0.startedAt == startedAt })?.id
            ?? UUID()
        let existingIndex = entries.firstIndex { $0.id == id }
        let shots = saveScreenshots ? HistoryPolicy.screenJPEGs(from: turns) : []
        let contextFilenames = HistoryPolicy.contextFilenames(from: turns)
        // Finishing and then dismissing records the same chat twice. Skip the second full rewrite.
        if let existingIndex {
            let existing = entries[existingIndex]
            if existing.turns.map(\.role) == turns.map(\.role.rawValue),
               existing.turns.map(\.text) == turns.map(\.text),
               existing.contextFilenames == contextFilenames,
               existing.hasScreenshot == !shots.isEmpty
            {
                return existing
            }
        }

        removeScreenshots(for: id)

        var turnRecords = turns.map {
            HistoryTurnRecord(role: $0.role.rawValue, text: $0.text, screenshotNames: [])
        }
        var wroteAnyScreenshot = false

        if !shots.isEmpty {
            try? fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
            var shotOrdinal = 0
            for item in shots {
                let name = "\(id.uuidString)-\(shotOrdinal).jpg"
                let url = screenshotsURL.appendingPathComponent(name)
                do {
                    try item.data.write(to: url, options: .atomic)
                    turnRecords[item.turnIndex].screenshotNames.append(name)
                    wroteAnyScreenshot = true
                    shotOrdinal += 1
                } catch {
                    continue
                }
            }
        }

        let entry = HistoryEntry(
            id: id,
            startedAt: startedAt,
            savedAt: Date(),
            turns: turnRecords,
            contextFilenames: contextFilenames,
            hasScreenshot: wroteAnyScreenshot
        )
        if let existingIndex {
            entries.remove(at: existingIndex)
        }
        entries.insert(entry, at: 0)
        while entries.count > maxEntries {
            removeScreenshots(for: entries.removeLast().id)
        }
        persistIndex()
        return entry
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        removeScreenshots(for: id)
        persistIndex()
    }

    /// Turning screenshots off removes the ones already saved. The chats stay.
    func removeAllScreenshots() {
        try? fileManager.removeItem(at: screenshotsURL)
        for index in entries.indices {
            entries[index].hasScreenshot = false
            for turn in entries[index].turns.indices {
                entries[index].turns[turn].screenshotNames = []
            }
        }
        persistIndex()
    }

    func loadScreenshot(for id: UUID) -> Data? {
        if let legacy = try? Data(contentsOf: screenshotURL(for: id)), !legacy.isEmpty {
            return legacy
        }
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        for name in entry.turns.flatMap(\.screenshotNames) {
            if let data = loadScreenshot(named: name, for: id) {
                return data
            }
        }
        return nil
    }

    func loadScreenshot(named name: String, for id: UUID) -> Data? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let base = (trimmed as NSString).lastPathComponent
        guard base.hasPrefix(id.uuidString) || base == "\(id.uuidString).jpg" else { return nil }
        let url = screenshotsURL.appendingPathComponent(base)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func screenshotURL(for id: UUID) -> URL {
        screenshotsURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    func reload() {
        entries = Self.loadEntries(from: indexURL, fileManager: fileManager)
    }

    private func removeScreenshots(for id: UUID) {
        try? fileManager.removeItem(at: screenshotURL(for: id))
        guard let items = try? fileManager.contentsOfDirectory(
            at: screenshotsURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let prefix = id.uuidString
        for url in items where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func persistIndex() {
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func loadEntries(from url: URL, fileManager: FileManager) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([HistoryEntry].self, from: data) {
            return entries
        }
        // The next save would overwrite every chat with an empty list, so keep the unreadable file.
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingLastPathComponent().appendingPathComponent("history.corrupt-\(stamp).json")
        try? fileManager.moveItem(at: url, to: aside)
        return []
    }
}
