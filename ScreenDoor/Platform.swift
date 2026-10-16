import SwiftUI
import UIKit

/// Vision Pro has no Liquid Glass and no haptics. These stand in for them, so the views read
/// the same on every platform.

enum Platform {
    #if os(visionOS)
    static let isVision = true
    #else
    static let isVision = false
    #endif
}

/// A haptic tap on iPhone and iPad. Does nothing on Vision Pro.
final class Haptic {
    enum Style { case light, medium, rigid, soft }

    #if os(visionOS)
    init(_ style: Style) {}
    func prepare() {}
    func play(intensity: CGFloat = 1) {}
    #else
    private let generator: UIImpactFeedbackGenerator

    init(_ style: Style) {
        let impact: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
        case .light: .light
        case .medium: .medium
        case .rigid: .rigid
        case .soft: .soft
        }
        generator = UIImpactFeedbackGenerator(style: impact)
    }

    func prepare() { generator.prepare() }
    func play(intensity: CGFloat = 1) { generator.impactOccurred(intensity: intensity) }
    #endif
}

extension View {
    /// Liquid Glass on iPhone and iPad, and the system glass material on Vision Pro.
    /// A tint marks a control that's on.
    @ViewBuilder
    func glass(in shape: some InsettableShape, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if os(visionOS)
        if let tint {
            background(tint, in: shape).hoverEffect(.highlight)
        } else if interactive {
            glassBackgroundEffect(in: shape).hoverEffect(.highlight)
        } else {
            glassBackgroundEffect(in: shape)
        }
        #else
        let base = tint.map { Glass.regular.tint($0) } ?? .regular
        glassEffect(interactive ? base.interactive() : base, in: shape)
        #endif
    }
}

/// Groups glass shapes so they blend on iPhone and iPad. On Vision Pro it's a plain container.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        #if os(visionOS)
        content
        #else
        GlassEffectContainer(spacing: spacing) { content }
        #endif
    }
}

extension View {
    /// The prominent and plain glass button styles, with Vision Pro's standard styles in their place.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if os(visionOS)
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #else
        if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        #endif
    }
}
