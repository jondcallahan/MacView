import SwiftUI
import RoyalVNCKit

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionModel
    @State private var hint: String?
    @State private var username = ""
    @State private var password = ""

    init(host: Host) {
        _model = State(initialValue: SessionModel(host: host))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RemoteScreen(model: model)
                .ignoresSafeArea()
                .opacity(model.status == .connected ? 1 : 0)

            statusOverlay
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { controls }
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
            showHint(mode == .mouse
                     ? "Drag to move the pointer. Tap to click. Tap with two fingers to right-click. Touch and hold, then drag to select."
                     : "Drag to look around. Pinch or double-tap to zoom.")
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
                let credential: VNCCredential = request.needsUsername
                    ? VNCUsernamePasswordCredential(username: username, password: password)
                    : VNCPasswordCredential(password: password)
                password = ""
                request.completion(credential)
            }
        } message: {
            Text(model.credentialRequest?.needsUsername == true
                 ? "Enter the name and password you use to log in to this Mac."
                 : "Enter the Screen Sharing password for this Mac.")
        }
        .onChange(of: model.credentialRequest == nil) { _, isNil in
            if !isNil { username = model.host.username }
        }
    }

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
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 0)

            Button("Disconnect", systemImage: "xmark") {
                model.disconnect()
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .frame(width: 48, height: 48)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .animation(.default, value: subtitle)
    }

    private var subtitle: String {
        switch model.status {
        case .connecting: stepTitle
        case .failed, .signInRejected: "Not connected"
        case .closed: "Disconnected"
        case .connected:
            (model.mode == .mouse || model.isKeyboardActive ? "You're in control" : "Viewing")
                + (model.route?.kind == .remote ? " · via Tailscale" : "")
        }
    }

    private var stepTitle: String {
        switch model.step {
        case .finding: "Finding…"
        case .connecting: "Connecting…"
        case .signingIn: "Signing in…"
        case .loadingScreen: "Loading screen…"
        }
    }

    private var stepDescription: String {
        let name = model.host.displayName
        return switch model.step {
        case .finding: "Looking for \(name) on your network and Tailscale…"
        case .connecting: model.route?.kind == .remote
            ? "Connecting to \(name) through Tailscale…"
            : "Connecting to \(name)…"
        case .signingIn: "Signing in to \(name)…"
        case .loadingScreen: "Loading \(name)'s screen…"
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .onTapGesture { withAnimation { self.hint = nil } }
                }

                if model.isKeyboardActive {
                    KeyRow(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        HStack(spacing: 0) {
                            modeButton("Look around", systemImage: "hand.draw", mode: .view)
                            modeButton("Mouse", systemImage: "cursorarrow", mode: .mouse)
                        }
                        .padding(4)
                        .glassEffect(.regular, in: .capsule)

                        toggleButton(model.isKeyboardActive ? "Hide keyboard" : "Show keyboard",
                                     systemImage: "keyboard",
                                     isOn: model.isKeyboardActive) {
                            model.isKeyboardActive.toggle()
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.controlsTop = $0 }
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
        .glassEffect(isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
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
                Text(model.host.remoteAddress.isEmpty
                     ? "\(message)\n\nCheck that the Mac is awake, Screen Sharing is on, and you're on the same network."
                     : "\(message)\n\nCheck that the Mac is awake and Screen Sharing is on.")
            } actions: {
                Button("Try again") { model.connect() }
                    .buttonStyle(.glassProminent)
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
            }
        case .signInRejected:
            ContentUnavailableView {
                Label("Sign-in didn't work", systemImage: "person.badge.key")
            } description: {
                Text("\(model.host.displayName) didn't accept that username and password. Use the name and password you log in to the Mac with.")
            } actions: {
                Button("Try again") { model.connect() }
                    .buttonStyle(.glassProminent)
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
            }
        case .closed:
            ContentUnavailableView {
                Label("Disconnected", systemImage: "desktopcomputer")
            } actions: {
                Button("Reconnect") { model.connect() }
                    .buttonStyle(.glassProminent)
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
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
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
        .scrollClipDisabled()
    }

    private func key(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title).font(.callout.weight(.medium)).frame(minWidth: 44, minHeight: 40)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .accessibilityLabel(label)
    }

    private func key(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage).font(.callout.weight(.semibold)).frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
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
        .glassEffect(isOn ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 12))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
