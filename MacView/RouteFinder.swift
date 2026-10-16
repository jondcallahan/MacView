import Foundation
import Network

struct Route: Equatable {
    enum Kind { case local, remote }
    let kind: Kind
    let address: String
}

/// Picks which of a Mac's addresses to connect to.
enum RouteFinder {
    /// How long the preferred route gets to answer before a later one that answered wins.
    static let headStart: TimeInterval = 2
    static let timeout: TimeInterval = 8

    private enum Event {
        case probed(Route, Bool)
        case headStartOver
    }

    /// Opens a TCP connection to every route at once and returns the most preferred one that
    /// answers. The first route gets a head start, so it wins whenever it's reachable.
    /// With a single route this returns it untested, so the VNC connection reports its own error.
    static func choose(_ routes: [Route], port: UInt16) async -> Route? {
        guard routes.count > 1 else { return routes.first }
        let preferred = routes[0]

        return await withTaskGroup(of: Event.self) { group in
            for route in routes {
                group.addTask { .probed(route, await probe(route.address, port: port)) }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(headStart))
                return .headStartOver
            }

            var pending = routes.count
            var reachable: [Route] = []
            var preferredDone = false
            var headStartOver = false
            for await event in group {
                switch event {
                case .probed(let route, let ok):
                    pending -= 1
                    if ok { reachable.append(route) }
                    if route == preferred { preferredDone = true }
                case .headStartOver:
                    headStartOver = true
                }

                if reachable.contains(preferred) {
                    group.cancelAll()
                    return preferred
                }
                if preferredDone || headStartOver,
                   let next = routes.first(where: reachable.contains) {
                    group.cancelAll()
                    return next
                }
                if pending == 0 {
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
    }

    private static let queue = DispatchQueue(label: "MacView.RouteFinder")

    /// Whether a TCP connection to the address opens within the timeout.
    private static func probe(_ address: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(address), port: nwPort, using: .tcp)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Only touched on `queue`.
                var finished = false
                let finish: (Bool) -> Void = { ok in
                    guard !finished else { return }
                    finished = true
                    connection.cancel()
                    continuation.resume(returning: ok)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: finish(true)
                    // Waiting means no route or the name didn't resolve, such as Tailscale being off.
                    case .waiting, .failed, .cancelled: finish(false)
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
