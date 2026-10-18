import Foundation

/* Block comment spanning lines.
   struct NotReal {}
*/
struct Item: Identifiable, Codable, Hashable, Sendable {
    enum Priority: Int, Codable, Sendable {
        case low, normal, high
    }

    let id: UUID
    var name: String
    var priority: Priority
    var isDone: Bool

    func renamed(_ newName: String) -> Item {
        var copy = self
        copy.name = newName
        return copy
    }
}
