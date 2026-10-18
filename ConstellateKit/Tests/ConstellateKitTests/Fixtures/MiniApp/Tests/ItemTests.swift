import Testing
@testable import MiniApp

struct ItemTests {
    @Test func renamedKeepsID() {
        let item = Item(id: UUID(), name: "A", priority: .normal, isDone: false)
        #expect(item.renamed("B").id == item.id)
    }

    @Test func storeRoundTrips() async throws {
        let store = ItemStore(fileURL: URL(fileURLWithPath: "/tmp/test.json"))
        try await store.save([])
        #expect(try await store.load().isEmpty)
    }
}
