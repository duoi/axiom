import Foundation
import Testing
@testable import Axiom

@Test func providerTableOmitsModelColumn() {
    #expect(EndpointTableColumns.titles == ["Name", "Host"])
    #expect(!EndpointTableColumns.titles.contains("Model"))
}
