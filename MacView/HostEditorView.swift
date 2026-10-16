import SwiftUI

struct HostEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var host: Host
    @State private var portText: String
    @State private var password: String
    private let isNew: Bool

    init(host: Host, isNew: Bool) {
        _host = State(initialValue: host)
        _portText = State(initialValue: String(host.port))
        _password = State(initialValue: Keychain.password(for: host.id) ?? "")
        self.isNew = isNew
    }

    private var trimmedAddress: String {
        host.address.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedRemoteAddress: String {
        host.remoteAddress.trimmingCharacters(in: .whitespaces)
    }

    /// Tailscale names a Mac after its local host name, lowercased: `Studio.local` becomes `studio`.
    private var suggestedRemoteAddress: String {
        let local = trimmedAddress.lowercased()
        guard local.hasSuffix(".local"), local.count > 6 else { return "studio or 100.64.0.1" }
        return String(local.dropLast(6)) + " or 100.64.0.1"
    }

    private var port: UInt16? {
        UInt16(portText)
    }

    private var canSave: Bool {
        (!trimmedAddress.isEmpty || !trimmedRemoteAddress.isEmpty) && port != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $host.name, prompt: Text("Studio Mac"))
                }

                Section {
                    LabeledContent("Local") {
                        TextField("Local", text: $host.address, prompt: Text("studio.local"))
                            .addressField()
                    }
                    LabeledContent("Tailscale") {
                        TextField("Tailscale", text: $host.remoteAddress, prompt: Text(suggestedRemoteAddress))
                            .addressField()
                    }
                    LabeledContent("Port") {
                        TextField("Port", text: $portText, prompt: Text("5900"))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    if port == nil {
                        Text("Enter a port from 1 to 65535. Screen Sharing uses 5900.")
                            .foregroundStyle(.red)
                    } else {
                        Text("MacView tries the local address first. If the Mac doesn't answer there, it uses the Tailscale address, which also works for any other VPN. To always use Tailscale, leave Local empty.")
                    }
                }

                Section {
                    TextField("Username", text: $host.username, prompt: Text("Mac account name"))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Sign-in")
                } footer: {
                    Text("Use the username and password you log in to this Mac with. Your password stays in Keychain on this device.")
                }
            }
            .navigationTitle(isNew ? "Add Mac" : "Edit Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        host.address = trimmedAddress
                        host.remoteAddress = trimmedRemoteAddress
                        host.port = port ?? 5900
                        store.save(host, password: password)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private extension View {
    func addressField() -> some View {
        keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
    }
}
