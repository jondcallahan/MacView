import SwiftUI

@main
struct ScreenDoorApp: App {
    @State private var store = HostStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ConnectTimeline.removeDevelopmentLogs()
    }

    static let listWindowID = "macs"

    var body: some Scene {
        // The list has a fixed value, so asking for it again brings the open one forward instead of adding another.
        WindowGroup(id: Self.listWindowID, for: String.self) { _ in
            HostListView()
                .environment(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.loadIfEmpty() }
                }
        } defaultValue: {
            Self.listWindowID
        }
        #if os(visionOS)
        .defaultSize(width: 560, height: 680)
        #endif

        // On iPad and Vision Pro, each Mac opens in its own window, so you can see several at once.
        WindowGroup("Mac", for: Host.ID.self) { $hostID in
            SessionWindow(hostID: hostID)
                .environment(store)
        }
        #if os(visionOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}

private struct SessionWindow: View {
    let hostID: Host.ID?
    @Environment(HostStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let host = store.hosts.first(where: { $0.id == hostID }) {
            SessionView(host: host, closeWindow: close)
                .id(host.id)
        } else {
            ContentUnavailableView("This Mac isn't in your list anymore", systemImage: "desktopcomputer")
        }
    }

    /// Brings the list of Macs back first. Otherwise, closing a full-screen window on iPad goes to the Home Screen.
    private func close() {
        openWindow(id: ScreenDoorApp.listWindowID, value: ScreenDoorApp.listWindowID)
        dismissWindow()
    }
}
