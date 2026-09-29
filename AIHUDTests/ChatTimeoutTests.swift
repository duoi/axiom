import Foundation
import Testing
@testable import Axiom

@Test func chatTimeoutDefaultsClampAndPersist() {
    let suite = "aihud.tests.chat-timeout.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(ChatTimeoutSettings.defaultSeconds == 45)
    #expect(ChatTimeoutSettings.load(from: defaults) == 45)
    #expect(ChatTimeoutSettings.clamp(5) == 10)
    #expect(ChatTimeoutSettings.clamp(900) == 600)
    ChatTimeoutSettings.save(120, to: defaults)
    #expect(ChatTimeoutSettings.load(from: defaults) == 120)
    #expect(ChatTimeoutSettings.resourceTimeout(forRequest: 45) == 90)
    let (session, _) = ChatClient.makeSession(
        host: "example.com",
        requestTimeout: ChatTimeoutSettings.load(from: defaults)
    )
    #expect(session.configuration.timeoutIntervalForRequest == 120)
    #expect(session.configuration.timeoutIntervalForResource == 240)
}
