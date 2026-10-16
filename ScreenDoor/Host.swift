import Foundation
import Observation
import Security

struct Host: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Address on the local network, such as `studio.local`.
    var address: String
    /// Address through Tailscale or another VPN, tried when the local address can't be reached.
    var remoteAddress: String = ""
    var port: UInt16 = 5900
    var username: String = ""
    /// The Mac's model identifier, such as "Macmini9,1", learned from Bonjour. It picks the icon.
    var model: String?

    init(name: String, address: String, remoteAddress: String = "", port: UInt16 = 5900, model: String? = nil) {
        self.name = name
        self.address = address
        self.remoteAddress = remoteAddress
        self.port = port
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        remoteAddress = try container.decodeIfPresent(String.self, forKey: .remoteAddress) ?? ""
        port = try container.decode(UInt16.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }

    var displayName: String {
        name.isEmpty ? (address.isEmpty ? remoteAddress : address) : name
    }

    /// Ways to reach the Mac, most preferred first.
    var routes: [Route] {
        var routes: [Route] = []
        if !address.isEmpty { routes.append(Route(kind: .local, address: address)) }
        if !remoteAddress.isEmpty { routes.append(Route(kind: .remote, address: remoteAddress)) }
        return routes
    }
}

@Observable
final class HostStore {
    private(set) var hosts: [Host] = []
    private let defaultsKey = "hosts"

    init() {
        loadIfEmpty()
    }

    /// iOS can launch the app before the device's first unlock, when UserDefaults reads as empty.
    /// Loading again once the app is in use keeps that empty list from replacing the saved one.
    func loadIfEmpty() {
        guard hosts.isEmpty,
              let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = saved
    }

    func save(_ host: Host, password: String?) {
        loadIfEmpty()
        // The first save on this install. iOS can keep Keychain items after an app is deleted,
        // so remove any passwords an earlier install left behind. This waits until now, rather
        // than launch, because a launch before the device's first unlock can't read the list.
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            Keychain.deleteAllPasswords()
        }
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        if let password {
            Keychain.setPassword(password, for: host.id)
        }
        persist()
    }

    /// Remembers a saved Mac's model, so its icon stays right away from home.
    func setModel(_ model: String, for id: UUID) {
        guard let index = hosts.firstIndex(where: { $0.id == id }), hosts[index].model != model else { return }
        hosts[index].model = model
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            Keychain.deletePassword(for: hosts[index].id)
        }
        hosts.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "ScreenDoor"

    private static func query(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    static func password(for id: UUID) -> String? {
        var query = query(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for id: UUID) {
        deletePassword(for: id)
        guard !password.isEmpty else { return }
        var item = query(for: id)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deletePassword(for id: UUID) {
        SecItemDelete(query(for: id) as CFDictionary)
    }

    static func deleteAllPasswords() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}
