import SwiftUI
import RoyalVNCKit

struct SessionView: View {
    @Environment(\.dismiss) private var dismissCover
    /// Closes the Mac's own window on iPad and Vision Pro. Without it, the session is a full-screen cover.
    var closeWindow: (() -> Void)?
    @State private var model: SessionModel
    @State private var hint: String?
    @State private var username = ""
    @State private var password = ""

    init(host: Host, closeWindow: (() -> Void)? = nil) {
        _model = State(initialValue: SessionModel(host: host))
        self.closeWindow = closeWindow
    }

    private func dismiss() {
        if let closeWindow { closeWindow() } else { dismissCover() }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RemoteScreen(model: model)
                .ignoresSafeArea()
                .opacity(model.status == .connected ? 1 : 0)

            statusOverlay
        }
        #if os(visionOS)
        // The window's own controls close it, and the session's controls sit below it.
        .ornament(visibility: model.status == .connected ? .visible : .hidden,
                  attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            controls.padding(.top, 12)
        }
        .onChange(of: model.status) { _, status in
            if status == .connected { showHint(Self.mouseHint) }
        }
        #else
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { controls }
        #endif
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: model.mode)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isKeyboardActive)
        .sensoryFeedback(.selection, trigger: model.latchedModifiers)
        .sensoryFeedback(trigger: model.status) { _, status in
            switch status {
            case .connected: .success
            case .failed, .signInRejected: .error
            default: nil
            }
        }
        .persistentSystemOverlays(.hidden)
        .task { model.connect() }
        .onDisappear { model.disconnect() }
        .onChange(of: model.mode) { _, mode in
            showHint(mode == .mouse ? Self.mouseHint : Self.lookHint)
        }
        .alert("Sign in to \(model.host.displayName)", isPresented: credentialAlertBinding) {
            if model.credentialRequest?.needsUsername == true {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button("Cancel", role: .cancel) {
                model.credentialRequest?.completion(nil)
            }
            Button("Sign in") {
                guard let request = model.credentialRequest else { return }
                let credential = SessionModel.credential(needsUsername: request.needsUsername,
                                                         username: username, password: password)
                password = ""
                request.completion(credential)
            }
        } message: {
            Text(model.credentialRequest?.needsUsername == true
                 ? "Enter the username and password you use to log in to this Mac."
                 : "Enter the Screen Sharing password for this Mac.")
        }
        .onChange(of: model.credentialRequest == nil) { _, isNil in
            if !isNil { username = model.host.username }
        }
    }

    #if os(visionOS)
    private static let mouseHint = "Look at something and tap to click. Pinch and drag to scroll. Pinch and hold, then drag to select, or let go to right-click."
    private static let lookHint = "Pinch and drag to look around. Pinch with both hands to zoom."
    #else
    private static let mouseHint = "Drag to move the pointer. Tap to click. Tap with two fingers to right-click. Touch and hold, then drag to select."
    private static let lookHint = "Drag to look around. Pinch or double-tap to zoom."
    #endif

    private var credentialAlertBinding: Binding<Bool> {
        Binding(
            get: { model.credentialRequest != nil },
            set: { if !$0, let request = model.credentialRequest { request.completion(nil) } }
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.host.displayName)
                    .font(.headline)
                    .lineLimit(1)
                // Until the screen shows, the centre of the screen carries the status.
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .glass(in: .capsule)

            Spacer(minLength: 0)

            Button {
                model.disconnect()
                dismiss()
            } label: {
                Label("Disconnect", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glass(in: .circle, interactive: true)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .animation(.default, value: subtitle)
    }

    private var subtitle: String? {
        guard model.status == .connected else { return nil }
        return (model.mode == .mouse || model.isKeyboardActive ? "You're in control" : "Viewing")
            + (model.route?.kind == .remote ? " · via Tailscale" : "")
    }

    /// The Mac's name is in the header, so this is just the step.
    private var stepDescription: String {
        switch model.step {
        case .finding: "Looking on your network and Tailscale…"
        case .connecting: model.route?.kind == .remote ? "Connecting through Tailscale…" : "Connecting…"
        case .signingIn: "Signing in…"
        case .loadingScreen: "Loading screen…"
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if model.status == .connected {
            VStack(spacing: 12) {
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        #if os(visionOS)
                        // The ornament doesn't limit its width, so keep the hint to a few short lines.
                        .frame(width: 460)
                        #endif
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glass(in: .rect(cornerRadius: 18))
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .onTapGesture { withAnimation { self.hint = nil } }
                }

                if model.isKeyboardActive {
                    KeyRow(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                GlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        #if os(visionOS)
                        // Vision Pro windows have no title, so the Mac's name goes here.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.host.displayName)
                                .font(.headline)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .glass(in: .capsule)
                        #endif
                        HStack(spacing: 0) {
                            modeButton("Look around", systemImage: "hand.draw", mode: .view)
                            modeButton("Mouse", systemImage: "cursorarrow", mode: .mouse)
                        }
                        .padding(4)
                        .glass(in: .capsule)

                        toggleButton(model.isKeyboardActive ? "Hide keyboard" : "Show keyboard",
                                     systemImage: "keyboard",
                                     isOn: model.isKeyboardActive) {
                            model.isKeyboardActive.toggle()
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            #if !os(visionOS)
            // On Vision Pro the controls and keyboard float outside the window, so nothing covers the screen.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.controlsTop = $0 }
            #endif
            .animation(.smooth, value: model.isKeyboardActive)
            .animation(.smooth, value: hint)
        }
    }

    private func modeButton(_ title: String, systemImage: String, mode: InputMode) -> some View {
        let isSelected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 64, height: 48)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        Capsule().fill(Color.accentColor)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy, value: model.mode)
    }

    private func toggleButton(_ title: String, systemImage: String, isOn: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 64, height: 56)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glass(in: .capsule, tint: isOn ? .accentColor : nil, interactive: true)
        .accessibilityLabel(title)
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.status {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(stepDescription)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: model.step)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't connect to \(model.host.displayName)", systemImage: "exclamationmark.triangle")
            } description: {
                Text([message, model.host.remoteAddress.isEmpty
                      ? "Make sure the Mac is awake, Screen Sharing is on, and you're on the same network."
                      : "Make sure the Mac is awake and Screen Sharing is on. If you're away from home, turn on Tailscale."]
                    .compactMap { $0 }.joined(separator: "\n\n"))
            } actions: {
                Button("Try again") { model.connect() }
                    .glassButton(prominent: true)
                Button("Close") { dismiss() }
                    .glassButton()
            }
        case .signInRejected:
            ContentUnavailableView {
                Label("Sign-in didn't work", systemImage: "person.badge.key")
            } description: {
                Text("\(model.host.displayName) didn't accept that username and password. Use the ones you log in to the Mac with.")
            } actions: {
                Button("Try again") { model.connect() }
                    .glassButton(prominent: true)
                Button("Close") { dismiss() }
                    .glassButton()
            }
        case .closed:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "desktopcomputer")
            } actions: {
                Button("Reconnect") { model.connect() }
                    .glassButton(prominent: true)
            }
        case .connected:
            EmptyView()
        }
    }

    private func showHint(_ text: String) {
        withAnimation { hint = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if hint == text { withAnimation { hint = nil } }
        }
    }
}

/// Mac keys the iOS keyboard doesn't have. Modifiers latch and apply to the next key you type.
private struct KeyRow: View {
    let model: SessionModel

    var body: some View {
        #if os(visionOS)
        // The ornament is as wide as its content, so there's nothing to scroll.
        keys
        #else
        ScrollView(.horizontal, showsIndicators: false) { keys }
            .scrollClipDisabled()
        #endif
    }

    private var keys: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                key("esc", label: "Escape") { model.press(.escape) }
                key("tab", label: "Tab") { model.press(.tab) }
                modifier("⌃", label: "Control", .control)
                modifier("⌥", label: "Option", .option)
                modifier("⌘", label: "Command", .command)
                modifier("⇧", label: "Shift", .shift)
                key(systemImage: "arrow.left", label: "Left arrow") { model.press(.leftArrow) }
                key(systemImage: "arrow.up", label: "Up arrow") { model.press(.upArrow) }
                key(systemImage: "arrow.down", label: "Down arrow") { model.press(.downArrow) }
                key(systemImage: "arrow.right", label: "Right arrow") { model.press(.rightArrow) }
            }
            .padding(.horizontal)
        }
    }

    private func key(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic(.light).play()
            action()
        } label: {
            Text(title).font(.callout.weight(.medium)).frame(minWidth: 44, minHeight: 40)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glass(in: .rect(cornerRadius: 12), interactive: true)
        .accessibilityLabel(label)
    }

    private func key(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic(.light).play()
            action()
        } label: {
            Image(systemName: systemImage).font(.callout.weight(.semibold)).frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .glass(in: .rect(cornerRadius: 12), interactive: true)
        .accessibilityLabel(label)
    }

    private func modifier(_ symbol: String, label: String, _ value: Modifiers) -> some View {
        let isOn = model.latchedModifiers.contains(value)
        return Button {
            model.toggleLatch(value)
        } label: {
            Text(symbol).font(.title3).frame(width: 44, height: 40)
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glass(in: .rect(cornerRadius: 12), tint: isOn ? .accentColor : nil, interactive: true)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
