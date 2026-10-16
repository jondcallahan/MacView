import SwiftUI

struct HostListView: View {
    @Environment(HostStore.self) private var store
    @State private var editingHost: Host?
    @State private var activeHost: Host?

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Macs yet", systemImage: "desktopcomputer")
                    } description: {
                        Text("Add a Mac to see and control its screen. On the Mac, turn on Screen Sharing in System Settings > General > Sharing.")
                    } actions: {
                        Button("Add Mac") { editingHost = Host(name: "", address: "") }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        ForEach(store.hosts) { host in
                            Button {
                                activeHost = host
                            } label: {
                                HostRow(host: host)
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
        }
    }
}

private struct HostRow: View {
    let host: Host

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.body.weight(.medium))
                if !host.name.isEmpty {
                    Text(host.address)
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
