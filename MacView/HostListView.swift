import SwiftUI

struct HostListView: View {
    @Environment(HostStore.self) private var store
    @State private var browser = MacBrowser()
    @State private var editingHost: Host?
    @State private var activeHost: Host?

    /// Macs found on the network that aren't saved yet.
    private var newMacs: [DiscoveredMac] {
        browser.macs.filter { mac in !store.hosts.contains { browser.mac(matching: $0) == mac } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty && newMacs.isEmpty {
                    ContentUnavailableView {
                        Label("No Macs yet", systemImage: "desktopcomputer")
                    } description: {
                        Text("Add a Mac to see and control its screen. On the Mac, turn on Screen Sharing in System Settings > General > Sharing. Macs on this network show up here by themselves.")
                    } actions: {
                        Button("Add Mac") { editingHost = Host(name: "", address: "") }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        if !store.hosts.isEmpty {
                            Section {
                                ForEach(store.hosts) { host in
                                    Button {
                                        activeHost = host
                                    } label: {
                                        HostRow(host: host, isNearby: browser.mac(matching: host) != nil)
                                    }
                                    .tint(.primary)
                                    .swipeActions(edge: .leading) {
                                        Button("Edit", systemImage: "pencil") { editingHost = host }
                                            .tint(.blue)
                                    }
                                    .contextMenu {
                                        Button("Edit", systemImage: "pencil") { editingHost = host }
                                    }
                                }
                                .onDelete(perform: store.delete)
                            }
                        }
                        if !newMacs.isEmpty {
                            Section {
                                ForEach(newMacs) { mac in
                                    Button {
                                        editingHost = Host(name: mac.name, address: mac.hostName, port: mac.port)
                                    } label: {
                                        DiscoveredRow(mac: mac)
                                    }
                                    .tint(.primary)
                                }
                            } header: {
                                Text("On This Network")
                            } footer: {
                                Text("Tap a Mac to add it.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Macs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mac", systemImage: "plus") {
                        editingHost = Host(name: "", address: "")
                    }
                }
            }
            .sheet(item: $editingHost) { host in
                HostEditorView(host: host, isNew: !store.hosts.contains { $0.id == host.id })
            }
            .fullScreenCover(item: $activeHost) { host in
                SessionView(host: host)
            }
            .onAppear { browser.start() }
            .onDisappear { browser.stop() }
        }
    }
}

private struct HostRow: View {
    let host: Host
    let isNearby: Bool

    private var detail: String {
        [host.name.isEmpty ? "" : host.address, host.remoteAddress.isEmpty ? "" : "Tailscale"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .overlay(alignment: .bottomTrailing) {
                    if isNearby {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                            .accessibilityLabel("On this network")
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.body.weight(.medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

private struct DiscoveredRow: View {
    let mac: DiscoveredMac

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                    .font(.body.weight(.medium))
                Text(mac.hostName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
