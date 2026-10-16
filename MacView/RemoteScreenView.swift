import SwiftUI
import UIKit
import RoyalVNCKit

struct RemoteScreen: UIViewRepresentable {
    let model: SessionModel

    func makeUIView(context: Context) -> RemoteScreenView {
        RemoteScreenView(model: model)
    }

    func updateUIView(_ view: RemoteScreenView, context: Context) {
        view.apply(mode: model.mode)
        view.setKeyboardActive(model.isKeyboardActive)
    }
}

/// Shows the Mac's screen in a zoomable scroll view and turns touches into pointer events.
final class RemoteScreenView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
    private let model: SessionModel
    private let scrollView = UIScrollView()
    private let screenView = UIView()
    private let cursorLayer = CALayer()
    private let keyInput: KeyInputView

    private var mode: InputMode = .view
    private var cursorPosition = CGPoint.zero
    private var cursorHotspot = CGPoint.zero
    private var pendingFramebuffer: VNCFramebuffer?
    private var displayLink: CADisplayLink?
    private var hasFittedOnce = false

    // Mouse-mode gestures
    private lazy var movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
    private lazy var scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
    private lazy var dragPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
    private lazy var clickTap = UITapGestureRecognizer(target: self, action: #selector(handleClick(_:)))
    private lazy var rightClickTap = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
    private lazy var pointerRightClick = UITapGestureRecognizer(target: self, action: #selector(handlePointerRightClick(_:)))
    private lazy var hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
    // View-mode gestures
    private lazy var zoomTap = UITapGestureRecognizer(target: self, action: #selector(handleZoomTap(_:)))

    private var mouseGestures: [UIGestureRecognizer] {
        [movePan, scrollPan, dragPress, clickTap, rightClickTap, pointerRightClick, hover]
    }

    private var lastPanTranslation = CGPoint.zero
    private var lastDragLocation = CGPoint.zero
    private var scrollRemainder = CGPoint.zero
    private var lastTouchWasPointer = false

    init(model: SessionModel) {
        self.model = model
        self.keyInput = KeyInputView(model: model)
        super.init(frame: .zero)
        backgroundColor = .black

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        addSubview(scrollView)

        screenView.layer.magnificationFilter = .linear
        screenView.layer.minificationFilter = .trilinear
        screenView.isAccessibilityElement = true
        screenView.accessibilityLabel = "Screen of \(model.host.displayName)"
        scrollView.addSubview(screenView)

        cursorLayer.zPosition = 10
        screenView.layer.addSublayer(cursorLayer)

        addSubview(keyInput)

        configureGestures()

        model.onFramebufferUpdate = { [weak self] framebuffer in
            self?.pendingFramebuffer = framebuffer
        }
        model.onCursorUpdate = { [weak self] cursor in
            self?.updateCursorImage(cursor)
        }
        addInteraction(UIPointerInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(renderIfNeeded))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let oldSize = scrollView.bounds.size
        scrollView.frame = bounds
        if oldSize != bounds.size {
            updateZoomLimits(refit: !hasFittedOnce || scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001)
        }
    }

    // MARK: Rendering

    /// Coalesces framebuffer updates to at most one image per display refresh.
    @objc private func renderIfNeeded() {
        guard let framebuffer = pendingFramebuffer else { return }
        pendingFramebuffer = nil

        let size = framebuffer.cgSize
        if screenView.bounds.size != size {
            screenView.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            cursorPosition = CGPoint(x: size.width / 2, y: size.height / 2)
            hasFittedOnce = false
            updateZoomLimits(refit: true)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screenView.layer.contents = framebuffer.cgImage
        CATransaction.commit()
    }

    private func updateCursorImage(_ cursor: VNCCursor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if cursor.isEmpty {
            cursorLayer.contents = nil
            cursorLayer.bounds = .zero
        } else {
            cursorLayer.contents = cursor.cgImage
            cursorLayer.bounds = CGRect(origin: .zero, size: cursor.cgSize)
            cursorHotspot = cursor.cgHotspot
        }
        positionCursorLayer()
        CATransaction.commit()
    }

    private func positionCursorLayer() {
        cursorLayer.anchorPoint = .zero
        cursorLayer.position = CGPoint(x: cursorPosition.x - cursorHotspot.x,
                                       y: cursorPosition.y - cursorHotspot.y)
    }

    // MARK: Zooming

    private func updateZoomLimits(refit: Bool) {
        let content = screenView.bounds.size
        guard content.width > 0, bounds.width > 0 else { return }
        let fit = min(bounds.width / content.width, bounds.height / content.height)
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 8, 2)
        if refit {
            scrollView.zoomScale = fit
            hasFittedOnce = true
        } else if scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
        }
        centerContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { screenView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    /// Keeps the screen centered when it's smaller than the viewport.
    private func centerContent() {
        let content = screenView.frame.size
        let insetX = max(0, (bounds.width - content.width) / 2)
        let insetY = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    @objc private func handleZoomTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale * 1.05 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: screenView)
            let scale = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }

    // MARK: Modes

    func apply(mode newMode: InputMode) {
        guard newMode != mode else { return }
        mode = newMode
        let isMouse = newMode == .mouse
        mouseGestures.forEach { $0.isEnabled = isMouse }
        zoomTap.isEnabled = !isMouse
        // In mouse mode, one finger drives the pointer, so the view follows the pointer instead of panning.
        scrollView.panGestureRecognizer.isEnabled = !isMouse
        if isMouse {
            model.mouseMove(to: cursorPosition)
            keepCursorVisible(animated: true)
        }
    }

    func setKeyboardActive(_ active: Bool) {
        if active, !keyInput.isFirstResponder {
            keyInput.becomeFirstResponder()
        } else if !active, keyInput.isFirstResponder {
            keyInput.resignFirstResponder()
        }
    }

    // MARK: Gestures

    private func configureGestures() {
        zoomTap.numberOfTapsRequired = 2
        screenView.addGestureRecognizer(zoomTap)
        screenView.isUserInteractionEnabled = true

        movePan.maximumNumberOfTouches = 1
        movePan.allowedScrollTypesMask = []

        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        scrollPan.allowedScrollTypesMask = .all

        dragPress.minimumPressDuration = 0.35
        dragPress.allowableMovement = 12

        rightClickTap.numberOfTouchesRequired = 2
        clickTap.require(toFail: rightClickTap)

        pointerRightClick.buttonMaskRequired = .secondary

        for gesture in mouseGestures {
            gesture.delegate = self
            gesture.isEnabled = false
            addGestureRecognizer(gesture)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        lastTouchWasPointer = touch.type == .indirectPointer
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Two-finger scrolling and pinch-to-zoom can happen together.
        (gestureRecognizer === scrollPan && other === scrollView.pinchGestureRecognizer)
            || (other === scrollPan && gestureRecognizer === scrollView.pinchGestureRecognizer)
            || gestureRecognizer === hover || other === hover
    }

    /// Converts a finger movement on the glass into a pointer movement on the Mac.
    private func pointerDelta(for translation: CGPoint) -> CGPoint {
        let scale = scrollView.zoomScale
        let speed = hypot(translation.x, translation.y)
        // Gentle acceleration: slow moves are precise, fast flicks cover more ground.
        let gain = 1.2 + min(speed / 18, 1.6)
        return CGPoint(x: translation.x / scale * gain, y: translation.y / scale * gain)
    }

    private func moveCursor(by delta: CGPoint) {
        let size = screenView.bounds.size
        cursorPosition.x = min(max(cursorPosition.x + delta.x, 0), size.width - 1)
        cursorPosition.y = min(max(cursorPosition.y + delta.y, 0), size.height - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionCursorLayer()
        CATransaction.commit()
        keepCursorVisible(animated: false)
    }

    @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let translation = gesture.translation(in: self)
            let step = CGPoint(x: translation.x - lastPanTranslation.x, y: translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            moveCursor(by: pointerDelta(for: step))
            model.mouseMove(to: cursorPosition)
        default:
            break
        }
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            lastDragLocation = location
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.mouseDown(.left, at: cursorPosition)
        case .changed:
            let step = CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
            lastDragLocation = location
            moveCursor(by: pointerDelta(for: step))
            model.mouseMove(to: cursorPosition)
        default:
            model.mouseUp(.left, at: cursorPosition)
        }
    }

    @objc private func handleClick(_ gesture: UITapGestureRecognizer) {
        if lastTouchWasPointer {
            cursorPosition = gesture.location(in: screenView)
            positionCursorLayer()
        }
        model.click(.left, at: cursorPosition)
    }

    @objc private func handleRightClick(_ gesture: UITapGestureRecognizer) {
        model.click(.right, at: cursorPosition)
    }

    @objc private func handlePointerRightClick(_ gesture: UITapGestureRecognizer) {
        cursorPosition = gesture.location(in: screenView)
        positionCursorLayer()
        model.click(.right, at: cursorPosition)
    }

    /// A trackpad or mouse attached to an iPad moves the Mac's pointer directly.
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        cursorPosition = gesture.location(in: screenView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionCursorLayer()
        CATransaction.commit()
        model.mouseMove(to: cursorPosition)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollRemainder = .zero
            lastPanTranslation = .zero
        case .changed:
            // Ignore scrolling while the user is clearly pinching.
            if scrollView.pinchGestureRecognizer?.state == .changed,
               abs(scrollView.pinchGestureRecognizer?.velocity ?? 0) > 0.3 {
                return
            }
            let translation = gesture.translation(in: self)
            scrollRemainder.x += translation.x - lastPanTranslation.x
            scrollRemainder.y += translation.y - lastPanTranslation.y
            lastPanTranslation = translation
            let stepSize: CGFloat = 10
            let vertical = Int(scrollRemainder.y / stepSize)
            if vertical != 0 {
                // Natural scrolling: fingers moving down reveal content above.
                model.scroll(vertical > 0 ? .up : .down, steps: UInt32(abs(vertical)), at: cursorPosition)
                scrollRemainder.y -= CGFloat(vertical) * stepSize
            }
            let horizontal = Int(scrollRemainder.x / stepSize)
            if horizontal != 0 {
                model.scroll(horizontal > 0 ? .left : .right, steps: UInt32(abs(horizontal)), at: cursorPosition)
                scrollRemainder.x -= CGFloat(horizontal) * stepSize
            }
        default:
            break
        }
    }

    /// Scrolls the viewport so the pointer stays on screen while zoomed in.
    private func keepCursorVisible(animated: Bool) {
        let point = screenView.convert(cursorPosition, to: scrollView)
        let margin: CGFloat = 60
        let visible = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size).insetBy(dx: margin, dy: margin)
        guard !visible.contains(point) else { return }
        var offset = scrollView.contentOffset
        if point.x < visible.minX { offset.x -= visible.minX - point.x }
        if point.x > visible.maxX { offset.x += point.x - visible.maxX }
        if point.y < visible.minY { offset.y -= visible.minY - point.y }
        if point.y > visible.maxY { offset.y += point.y - visible.maxY }
        let inset = scrollView.contentInset
        offset.x = min(max(offset.x, -inset.left), max(-inset.left, scrollView.contentSize.width - scrollView.bounds.width + inset.right))
        offset.y = min(max(offset.y, -inset.top), max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom))
        scrollView.setContentOffset(offset, animated: animated)
    }

    // MARK: Pointer

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // Hide the iPad pointer in mouse mode so only the Mac's pointer shows.
        mode == .mouse ? .hidden() : nil
    }
}
