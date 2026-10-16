import Foundation
import Network
import Observation

struct DiscoveredMac: Identifiable, Hashable {
    var id: String { name }
    /// The Mac's computer name, as Screen Sharing advertises it.
    let name: String
    /// Its local host name, such as `Studio.local`.
    let hostName: String
    let port: UInt16
}

/// Finds Macs on the local network that have Screen Sharing on. They advertise `_rfb._tcp`.
@MainActor
@Observable
final class MacBrowser {
    private(set) var macs: [DiscoveredMac] = []

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolvers: [String: Resolver] = [:]

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.update(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.stop() }
        resolvers = [:]
    }

    /// The discovered Mac a saved host points at, if it's on this network now.
    func mac(matching host: Host) -> DiscoveredMac? {
        let address = Self.normalized(host.address)
        return macs.first { Self.normalized($0.hostName) == address || (!host.name.isEmpty && $0.name == host.name) }
    }

    private static func normalized(_ name: String) -> String {
        var name = name.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        return name
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var names = Set<String>()
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            names.insert(name)
            // A Mac on several interfaces shows up once per interface. Resolve it once.
            guard resolvers[name] == nil, !macs.contains(where: { $0.name == name }) else { continue }
            resolvers[name] = Resolver(name: name, type: type, domain: domain) { [weak self] hostName, port in
                self?.resolved(DiscoveredMac(name: name, hostName: hostName, port: port))
            }
        }
        macs.removeAll { !names.contains($0.name) }
        for name in resolvers.keys where !names.contains(name) {
            resolvers.removeValue(forKey: name)?.stop()
        }
    }

    private func resolved(_ mac: DiscoveredMac) {
        resolvers.removeValue(forKey: mac.name)
        guard !macs.contains(where: { $0.name == mac.name }) else { return }
        macs.append(mac)
        macs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Looks up a Bonjour service's host name. NWBrowser gives only the service name, and a host name
/// keeps working when the Mac's IP address changes.
private final class Resolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private let completion: @MainActor (String, UInt16) -> Void

    init(name: String, type: String, domain: String,
         completion: @escaping @MainActor (String, UInt16) -> Void) {
        service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        service.delegate = self
        service.resolve(withTimeout: 10)
    }

    func stop() {
        service.delegate = nil
        service.stop()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard var hostName = sender.hostName, sender.port > 0 else { return }
        if hostName.hasSuffix(".") { hostName.removeLast() }
        let port = UInt16(sender.port)
        stop()
        MainActor.assumeIsolated { completion(hostName, port) }
    }
}
