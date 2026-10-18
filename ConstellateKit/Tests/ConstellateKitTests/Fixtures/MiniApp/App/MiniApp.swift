import SwiftUI

@main
struct MiniApp: App {
    @State private var service = ItemService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(service)
        }
    }
}
