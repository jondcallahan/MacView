import Foundation
import Observation
import RoyalVNCKit

enum InputMode {
    /// Pan and zoom only. Nothing is sent to the Mac.
    case view
    /// The screen acts like a trackpad that drives the Mac's pointer.
    case mouse
}

struct Modifiers: OptionSet, Hashable {
    let rawValue: Int
    static let control = Modifiers(rawValue: 1 << 0)
    static let option = Modifiers(rawValue: 1 << 1)
    static let command = Modifiers(rawValue: 1 << 2)
    static let shift = Modifiers(rawValue: 1 << 3)

    var keyCodes: [VNCKeyCode] {
        var codes: [VNCKeyCode] = []
        if contains(.control) { codes.append(.control) }
        if contains(.option) { codes.append(.option) }
        if contains(.command) { codes.append(.command) }
        if contains(.shift) { codes.append(.shift) }
        return codes
    }
}

struct CredentialRequest {
    let needsUsername: Bool
    let completion: (VNCCredential?) -> Void
}

@MainActor
@Observable
final class SessionModel {
    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
        case signInRejected
        case closed
    }

    /// Where a connection has got to, shown while `status` is `.connecting`.
    enum Step {
        case finding
        case connecting
        case signingIn
        case loadingScreen
    }

    let host: Host
    /// Becomes `.connected` once the first picture of the screen arrives.
    private(set) var status: Status = .connecting
    private(set) var step: Step = .connecting
    private(set) var framebufferSize: CGSize = .zero
    var mode: InputMode = .view
    var isKeyboardActive = false
    /// Modifiers the user latched from the key row. They apply to the next key, then clear.
    var latchedModifiers: Modifiers = []
    var credentialRequest: CredentialRequest?
    /// Top edge of the bottom controls in window coordinates, so the screen can slide above them.
    var controlsTop: CGFloat = 0
    /// The address this session is using, once one answered.
    private(set) var route: Route?

    @ObservationIgnored private var connection: VNCConnection?
    @ObservationIgnored private var timeline = ConnectTimeline()
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var bridge: DelegateBridge?
    @ObservationIgnored private var triedSavedCredentials = false
    @ObservationIgnored private var userClosed = false
    @ObservationIgnored private var cancelledSignIn = false

    /// Called on the main thread when the framebuffer changes. The view pulls a fresh image.
    @ObservationIgnored var onFramebufferUpdate: ((VNCFramebuffer) -> Void)?
    @ObservationIgnored var onCursorUpdate: ((VNCCursor) -> Void)?

    init(host: Host) {
        self.host = host
    }

    // MARK: Connection

    func connect() {
        userClosed = false
        cancelledSignIn = false
        triedSavedCredentials = false
        status = .connecting
        step = host.routes.count > 1 ? .finding : .connecting
        route = nil
        timeline = ConnectTimeline()

        routeTask?.cancel()
        routeTask = Task { [weak self, host] in
            let route = await RouteFinder.choose(host.routes, port: host.port)
            self?.timeline.mark("route")
            guard let self, !Task.isCancelled, !self.userClosed else { return }
            guard let route else {
                self.status = .failed(host.remoteAddress.isEmpty
                    ? "The Mac didn't answer."
                    : "The Mac didn't answer on your network or through Tailscale. If you're away from home, turn on Tailscale and try again.")
                return
            }
            self.route = route
            self.step = .connecting
            self.open(route)
        }
    }

    private func open(_ route: Route) {
        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: route.address,
            port: host.port,
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsEvenIfInUseLocally,
            isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit,
            frameEncodings: .default
        )
        let connection = VNCConnection(settings: settings)
        let bridge = DelegateBridge(model: self)
        connection.delegate = bridge
        self.connection = connection
        self.bridge = bridge
        connection.connect()
    }

    func disconnect() {
        userClosed = true
        routeTask?.cancel()
        connection?.disconnect()
        status = .closed
    }

    fileprivate func stateChanged(_ state: VNCConnection.ConnectionState) {
        switch state.status {
        case .connecting:
            status = .connecting
        case .connected:
            // Signed in. The screen shows once its first picture arrives.
            timeline.mark("signed in")
            step = .loadingScreen
        case .disconnecting:
            break
        case .disconnected:
            connection?.delegate = nil
            connection = nil
            bridge = nil
            guard !userClosed, !cancelledSignIn else { status = .closed; return }
            if let error = state.error {
                if let vncError = error as? VNCError, vncError.isAuthenticationError {
                    status = .signInRejected
                } else if let vncError = error as? VNCError, !vncError.shouldDisplayToUser {
                    status = .closed
                } else {
                    status = .failed(error.localizedDescription)
                }
            } else {
                status = .failed("The Mac ended the session.")
            }
        @unknown default:
            break
        }
    }

    fileprivate func credentialNeeded(for type: VNCAuthenticationType,
                                      completion: @escaping (VNCCredential?) -> Void) {
        timeline.mark("handshake")
        step = .signingIn
        let saved = Keychain.password(for: host.id)
        if !triedSavedCredentials, let saved, !saved.isEmpty,
           !type.requiresUsername || !host.username.isEmpty {
            triedSavedCredentials = true
            completion(credential(for: type, username: host.username, password: saved))
            return
        }
        credentialRequest = CredentialRequest(needsUsername: type.requiresUsername) { [weak self] credential in
            if credential == nil { self?.cancelledSignIn = true }
            completion(credential)
            self?.credentialRequest = nil
        }
    }

    func credential(for type: VNCAuthenticationType, username: String, password: String) -> VNCCredential {
        type.requiresUsername
            ? VNCUsernamePasswordCredential(username: username, password: password)
            : VNCPasswordCredential(password: password)
    }

    fileprivate func framebufferCreated(_ framebuffer: VNCFramebuffer) {
        framebufferSize = framebuffer.cgSize
        onFramebufferUpdate?(framebuffer)
    }

    fileprivate func framebufferUpdated(_ framebuffer: VNCFramebuffer) {
        onFramebufferUpdate?(framebuffer)
        guard status == .connecting, step == .loadingScreen else { return }
        status = .connected
        timeline.mark("first picture")
        timeline.save(summary: "\(host.displayName) via \(route?.kind == .remote ? "Tailscale" : "local"), "
                      + "\(Int(framebufferSize.width))×\(Int(framebufferSize.height))")
    }

    // MARK: Mouse

    func mouseMove(to point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseMove(x: x, y: y)
    }

    func mouseDown(_ button: VNCMouseButton, at point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseButtonDown(button, x: x, y: y)
    }

    func mouseUp(_ button: VNCMouseButton, at point: CGPoint) {
        guard let (x, y) = clamp(point) else { return }
        connection?.mouseButtonUp(button, x: x, y: y)
    }

    func click(_ button: VNCMouseButton, at point: CGPoint) {
        mouseDown(button, at: point)
        mouseUp(button, at: point)
    }

    func scroll(_ wheel: VNCMouseWheel, steps: UInt32, at point: CGPoint) {
        guard steps > 0, let (x, y) = clamp(point) else { return }
        connection?.mouseWheel(wheel, x: x, y: y, steps: steps)
    }

    private func clamp(_ point: CGPoint) -> (UInt16, UInt16)? {
        guard framebufferSize != .zero else { return nil }
        let x = min(max(point.x, 0), framebufferSize.width - 1)
        let y = min(max(point.y, 0), framebufferSize.height - 1)
        return (UInt16(x), UInt16(y))
    }

    // MARK: Keyboard

    /// Sends one key press, wrapped in any held or latched modifiers.
    func press(_ key: VNCKeyCode, modifiers: Modifiers = []) {
        let all = modifiers.union(latchedModifiers)
        let modifierKeys = all.keyCodes
        modifierKeys.forEach { connection?.keyDown($0) }
        connection?.keyDown(key)
        connection?.keyUp(key)
        modifierKeys.reversed().forEach { connection?.keyUp($0) }
        latchedModifiers = []
    }

    func typeText(_ text: String) {
        for character in text {
            if character.isNewline {
                press(.return)
            } else {
                for key in VNCKeyCode.withCharacter(character) {
                    press(key)
                }
            }
        }
    }

    func keyDown(_ key: VNCKeyCode) { connection?.keyDown(key) }
    func keyUp(_ key: VNCKeyCode) { connection?.keyUp(key) }

    func toggleLatch(_ modifier: Modifiers) {
        latchedModifiers.formSymmetricDifference(modifier)
    }
}

/// RoyalVNCKit calls its delegate on background queues. This hops each call to the main actor.
private final class DelegateBridge: VNCConnectionDelegate {
    weak var model: SessionModel?

    init(model: SessionModel) {
        self.model = model
    }

    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        Task { @MainActor [weak self] in self?.model?.stateChanged(connectionState) }
    }

    func connection(_ connection: VNCConnection,
                    credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping (VNCCredential?) -> Void) {
        Task { @MainActor [weak self] in
            guard let model = self?.model else { completion(nil); return }
            model.credentialNeeded(for: authenticationType, completion: completion)
        }
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in self?.model?.framebufferCreated(framebuffer) }
    }

    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in self?.model?.framebufferCreated(framebuffer) }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        Task { @MainActor [weak self] in self?.model?.framebufferUpdated(framebuffer) }
    }

    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        Task { @MainActor [weak self] in self?.model?.onCursorUpdate?(cursor) }
    }
}

/// Times each step of connecting and keeps the last few results in Documents/connect-timing.log,
/// to see where a slow connection spends its time.
private struct ConnectTimeline {
    private let start = ContinuousClock.now
    private var last = ContinuousClock.now
    private var steps: [String] = []

    mutating func mark(_ step: String) {
        let now = ContinuousClock.now
        steps.append("\(step) \(Self.ms(now - last))")
        last = now
    }

    func save(summary: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(summary): "
            + steps.joined(separator: ", ") + ", total \(Self.ms(ContinuousClock.now - start))"
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "connect-timing.log") else { return }
        let previous = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").suffix(19).map(String.init) ?? []
        try? (previous + [line]).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func ms(_ duration: Duration) -> String {
        "\(Int(duration / .milliseconds(1)))ms"
    }
}
