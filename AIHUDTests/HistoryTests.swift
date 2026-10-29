import Foundation
import Testing
@testable import Axiom

@Test func historyOffStoresNothing() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let session = finishedSession(
        prompt: "secret prompt",
        reply: "secret reply",
        chips: [
            Chip(id: UUID(), name: "notes.txt", payload: .text("file body")),
            Chip(id: UUID(), name: "Screen", payload: .jpeg(Data([0xFF, 0xD8])), isScreen: true)
        ]
    )

    let recorded = store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: false,
        saveScreenshots: true
    )

    #expect(recorded == nil)
    #expect(store.entries.isEmpty)
    #expect(screenshotFiles(in: root).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("history.json").path))
}

@Test func historyOnStoresExchangeAndFilenamesNotContents() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let body = "do not persist this file body"
    let session = finishedSession(
        prompt: "What is in the file?",
        reply: "A short answer.",
        chips: [
            Chip(id: UUID(), name: "/Users/me/secret/notes.txt", payload: .text(body)),
            Chip(id: UUID(), name: "Screen", payload: .jpeg(Data([0xFF, 0xD8, 0xFF])), isScreen: true)
        ]
    )

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    #expect(entry.turns.count == 2)
    #expect(entry.turns[0].role == "user")
    #expect(entry.turns[0].text == "What is in the file?")
    #expect(entry.turns[1].role == "assistant")
    #expect(entry.turns[1].text == "A short answer.")
    #expect(entry.contextFilenames == ["notes.txt"])
    #expect(entry.hasScreenshot == false)
    #expect(screenshotFiles(in: root).isEmpty)

    let json = try Data(contentsOf: root.appendingPathComponent("history.json"))
    let text = String(decoding: json, as: UTF8.self)
    #expect(!text.contains(body))
    #expect(!text.contains("/Users/me/secret"))
    #expect(text.contains("notes.txt"))
}

@Test func screenshotOptionOffKeepsNoImageData() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    let session = finishedSession(
        prompt: "Look at this",
        reply: "Seen.",
        chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(jpeg), isScreen: true)]
    )

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    #expect(entry.hasScreenshot == false)
    #expect(store.loadScreenshot(for: entry.id) == nil)
    #expect(screenshotFiles(in: root).isEmpty)
    let json = String(decoding: try Data(contentsOf: root.appendingPathComponent("history.json")), as: UTF8.self)
    #expect(!json.contains("FFD8"))
}

@Test func screenshotOptionOnKeepsImageWithChat() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
    let session = finishedSession(
        prompt: "Look at this",
        reply: "Seen.",
        chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(jpeg), isScreen: true)]
    )

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: true
    ))

    #expect(entry.hasScreenshot == true)
    #expect(store.loadScreenshot(for: entry.id) == jpeg)
    #expect(screenshotFiles(in: root).count == 1)
}

@Test func ghostExcludedSessionIsNotStored() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let session = finishedSession(prompt: "private", reply: "ok")

    let recorded = store.record(
        session: session,
        excludeFromHistory: true,
        historyEnabled: true,
        saveScreenshots: true
    )

    #expect(recorded == nil)
    #expect(store.entries.isEmpty)
}

@Test func deleteRemovesChatAndScreenshot() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xDB])
    let session = finishedSession(
        prompt: "capture",
        reply: "done",
        chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(jpeg), isScreen: true)]
    )
    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: true
    ))
    #expect(store.loadScreenshot(for: entry.id) == jpeg)

    store.delete(id: entry.id)

    #expect(store.entries.isEmpty)
    #expect(store.loadScreenshot(for: entry.id) == nil)
    #expect(screenshotFiles(in: root).isEmpty)
}

@Test func historyPolicyRequiresCompletedExchange() {
    var incomplete = Session()
    incomplete.draft = "hi"
    _ = incomplete.send()
    #expect(
        !HistoryPolicy.shouldRecord(
            historyEnabled: true,
            excludeFromHistory: false,
            turns: incomplete.turns
        )
    )

    incomplete.receiveToken("yo")
    incomplete.finish()
    #expect(
        HistoryPolicy.shouldRecord(
            historyEnabled: true,
            excludeFromHistory: false,
            turns: incomplete.turns
        )
    )
}

@Test func completedExchangeIsStoredWhenHistoryOnAndNotGhostExcluded() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi there")
    session.finish()

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    #expect(entry.turns.map(\.text) == ["Hello", "Hi there"])
    #expect(store.entries.count == 1)
}

@Test func thinkingPhaseKeepsFinishedTurnInExpandableThreadAndHistory() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi there")
    session.finish()

    session.draft = "And then?"
    _ = session.send()
    #expect(session.phase == .waiting)

    let rows = Transcript.rows(in: session, expanded: true)
    #expect(rows.contains { $0.kind == .assistant && $0.text == "Hi there" && !$0.live })
    #expect(rows.contains { $0.live && $0.text.isEmpty })

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))
    #expect(entry.turns.contains { $0.role == "assistant" && $0.text == "Hi there" })
}

@Test func uncommittedLiveReplySurvivesFollowUpSend() {
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi there")
    // Simulate a stuck streaming UI that was forced finished without finish():
    session.phase = .finished
    #expect(session.turns.count == 1)

    session.draft = "And then?"
    _ = session.send()
    #expect(session.phase == .waiting)
    #expect(session.turns.map(\.text) == ["Hello", "Hi there", "And then?"])
    let rows = Transcript.rows(in: session, expanded: true)
    #expect(rows.contains { $0.kind == .assistant && $0.text == "Hi there" && !$0.live })
}

@Test func streamingReplyWithoutFinishStillStoresCompletedExchange() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi there")
    #expect(session.phase == .streaming)

    let entry = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))
    #expect(entry.turns.map(\.text) == ["Hello", "Hi there"])
}

@Test func historyUpsertsSameSessionInsteadOfDuplicating() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    var session = Session()
    session.draft = "Hello"
    _ = session.send()
    session.receiveToken("Hi")
    session.finish()
    _ = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    session.draft = "Again"
    _ = session.send()
    session.receiveToken("There")
    session.finish()
    _ = try #require(store.record(
        session: session,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    #expect(store.entries.count == 1)
    #expect(store.entries[0].turns.map(\.text) == ["Hello", "Hi", "Again", "There"])
}

@Test func oneConversationPerSessionIncludesEveryTurnAndScreenshot() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x41])

    var first = Session()
    first.draft = "Look at this"
    _ = first.send(
        attachedJPEG: jpeg,
        attachmentName: "Window"
    )
    first.receiveToken("I see a window.")
    first.finish()
    _ = try #require(store.record(
        session: first,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: true
    ))

    first.draft = "What color is it?"
    _ = first.send()
    first.receiveToken("Mostly blue.")
    first.finish()
    let firstEntry = try #require(store.record(
        session: first,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: true
    ))

    #expect(store.entries.count == 1)
    #expect(firstEntry.turns.map(\.text) == [
        "Look at this",
        "I see a window.",
        "What color is it?",
        "Mostly blue."
    ])
    #expect(firstEntry.turns.map(\.role) == ["user", "assistant", "user", "assistant"])
    #expect(firstEntry.title == "Look at this")
    #expect(firstEntry.hasScreenshot)
    #expect(!firstEntry.turns[0].screenshotNames.isEmpty)
    let shot = try #require(store.loadScreenshot(
        named: firstEntry.turns[0].screenshotNames[0],
        for: firstEntry.id
    ))
    #expect(shot == jpeg)

    var second = Session()
    second.draft = "Separate chat"
    _ = second.send()
    second.receiveToken("New thread.")
    second.finish()
    let secondEntry = try #require(store.record(
        session: second,
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    ))

    #expect(store.entries.count == 2)
    #expect(secondEntry.id != firstEntry.id)
    #expect(secondEntry.turns.map(\.text) == ["Separate chat", "New thread."])
    #expect(!secondEntry.hasScreenshot)
}

@Test @MainActor func simulateIncomingStreamCommitsAssistantTurn() {
    let model = HUDModel(store: .isolated())
    model.simulateIncomingStream("Hi there")
    #expect(model.session.phase == .finished)
    #expect(model.session.turns.count == 2)
    #expect(model.session.turns.last?.role == .assistant)
    #expect(model.session.turns.last?.text == "Hi there")
}

@Test func historySettingsDefaultOff() {
    let suite = "aihud.tests.history-settings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!HistorySettings.loadEnabled(from: defaults))
    #expect(!HistorySettings.loadSaveScreenshots(from: defaults))
    HistorySettings.saveEnabled(true, to: defaults)
    HistorySettings.saveSaveScreenshots(true, to: defaults)
    #expect(HistorySettings.loadEnabled(from: defaults))
    #expect(HistorySettings.loadSaveScreenshots(from: defaults))
}

private func finishedSession(
    prompt: String,
    reply: String,
    chips: [Chip] = []
) -> Session {
    var session = Session()
    session.chips = chips
    session.draft = prompt
    _ = session.send()
    session.receiveToken(reply)
    session.finish()
    return session
}

private func makeHistoryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("aihud-history-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func screenshotFiles(in root: URL) -> [URL] {
    let shots = root.appendingPathComponent("screenshots", isDirectory: true)
    guard let items = try? FileManager.default.contentsOfDirectory(
        at: shots,
        includingPropertiesForKeys: nil
    ) else {
        return []
    }
    return items.filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
}

@Test func unreadableHistoryIsSetAsideNotOverwritten() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = root.appendingPathComponent("history.json")
    try Data("[{\"from a newer version\": true}]".utf8).write(to: index)

    let store = HistoryStore(root: root)
    #expect(store.entries.isEmpty)
    store.record(
        session: finishedSession(prompt: "Hi", reply: "Hello"),
        excludeFromHistory: false,
        historyEnabled: true,
        saveScreenshots: false
    )
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    let kept = try #require(names.first { $0.hasPrefix("history.corrupt-") })
    #expect(try Data(contentsOf: root.appendingPathComponent(kept)) == Data("[{\"from a newer version\": true}]".utf8))
}

@Test func recordingAnUnchangedChatAgainWritesNothing() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let session = finishedSession(
        prompt: "Hi",
        reply: "Hello",
        chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(Data([0xFF, 0xD8])), isScreen: true)]
    )
    let first = try #require(store.record(session: session, excludeFromHistory: false, historyEnabled: true, saveScreenshots: true))
    let shot = try #require(screenshotFiles(in: root).first)
    try FileManager.default.removeItem(at: shot)

    let second = try #require(store.record(session: session, excludeFromHistory: false, historyEnabled: true, saveScreenshots: true))
    #expect(second.savedAt == first.savedAt)
    #expect(screenshotFiles(in: root).isEmpty)
}

@Test func historyKeepsTheNewestChatsAndTheirScreenshotsOnly() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root, maxEntries: 2)
    var ids: [UUID] = []
    for prompt in ["one", "two", "three"] {
        let session = finishedSession(
            prompt: prompt,
            reply: "ok",
            chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(Data([0xFF, 0xD8])), isScreen: true)]
        )
        let entry = try #require(store.record(session: session, excludeFromHistory: false, historyEnabled: true, saveScreenshots: true))
        ids.append(entry.id)
    }
    #expect(store.entries.map(\.id) == [ids[2], ids[1]])
    #expect(!screenshotFiles(in: root).contains { $0.lastPathComponent.hasPrefix(ids[0].uuidString) })
    #expect(screenshotFiles(in: root).count == 2)
}

@Test func turningScreenshotsOffDeletesTheSavedOnes() throws {
    let root = try makeHistoryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryStore(root: root)
    let session = finishedSession(
        prompt: "Hi",
        reply: "Hello",
        chips: [Chip(id: UUID(), name: "Screen", payload: .jpeg(Data([0xFF, 0xD8])), isScreen: true)]
    )
    store.record(session: session, excludeFromHistory: false, historyEnabled: true, saveScreenshots: true)
    #expect(screenshotFiles(in: root).count == 1)

    store.removeAllScreenshots()
    #expect(screenshotFiles(in: root).isEmpty)
    #expect(store.entries.first?.hasScreenshot == false)
    #expect(store.entries.first?.turns.allSatisfy { $0.screenshotNames.isEmpty } == true)
    #expect(store.entries.first?.turns.first?.text == "Hi")
}
