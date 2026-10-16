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

    private var port: UInt16? {
        UInt16(portText)
    }

    private var canSave: Bool {
        !trimmedAddress.isEmpty && port != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $host.name, prompt: Text("Studio Mac"))
                    TextField("Address", text: $host.address, prompt: Text("studio.local or 192.168.1.20"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Port") {
                        TextField("Port", text: $portText, prompt: Text("5900"))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if port == nil {
                        Text("Enter a port from 1 to 65535. Screen Sharing uses 5900.")
                            .foregroundStyle(.red)
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
                    Text("Use the name and password you use to log in to this Mac. Your password stays in Keychain on this device.")
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
