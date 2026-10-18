import Foundation

protocol ItemRepository: Sendable {
    func load() async throws -> [Item]
    func save(_ items: [Item]) async throws
}

actor ItemStore: ItemRepository {
    private var cache: [Item] = []
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async throws -> [Item] {
        if cache.isEmpty {
            let data = try Data(contentsOf: fileURL)
            cache = try JSONDecoder().decode([Item].self, from: data)
        }
        return cache
    }

    func save(_ items: [Item]) async throws {
        cache = items
        let data = try JSONEncoder().encode(items)
        try data.write(to: fileURL)
    }
}
