import Foundation
import Observation

@Observable
@MainActor
final class ItemService {
    private(set) var items: [Item] = []
    private let repository: any ItemRepository

    init(repository: any ItemRepository = ItemStore(fileURL: URL(fileURLWithPath: "/tmp/items.json"))) {
        self.repository = repository
    }

    func refresh() async {
        items = (try? await repository.load()) ?? []
    }

    func add(_ item: Item) async throws {
        items.append(item)
        try await repository.save(items)
    }
}
