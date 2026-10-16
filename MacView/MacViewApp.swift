import SwiftUI

@main
struct MacViewApp: App {
    @State private var store = HostStore()

    init() {
        ConnectTimeline.removeDevelopmentLogs()
    }

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environment(store)
        }
    }
}
