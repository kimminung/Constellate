import SwiftUI

/// Shows the list of items. A comment mentioning `struct Fake: View` must be ignored.
struct ContentView: View {
    @Environment(ItemService.self) private var service
    @State private var isPresentingEditor = false
    let title = "Items // not a comment: struct Bogus {"

    var body: some View {
        NavigationStack {
            List(service.items) { item in
                ItemRow(item: item)
            }
            .navigationTitle(title)
            .toolbar {
                Button("Add") { isPresentingEditor = true }
            }
        }
        .task { await service.refresh() }
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        Text("\(item.name) · \(item.priorityLabel)")
    }
}
