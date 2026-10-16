import SwiftUI

@main
struct ScreenDoorApp: App {
    @State private var store = HostStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ConnectTimeline.removeDevelopmentLogs()
    }

    var body: some Scene {
        WindowGroup {
            HostListView()
                .environment(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.loadIfEmpty() }
                }
        }
    }
}
