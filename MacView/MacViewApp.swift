import SwiftUI

@main
struct MacViewApp: App {
    @State private var store = HostStore()

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environment(store)
        }
    }
}
