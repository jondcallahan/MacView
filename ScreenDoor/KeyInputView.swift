import UIKit
import RoyalVNCKit

/// An invisible view that takes keyboard focus. The on-screen keyboard types through `UIKeyInput`;
/// a hardware keyboard sends raw key presses, so shortcuts like ⌘C reach the Mac.
final class KeyInputView: UIView, UIKeyInput {
    private let model: SessionModel

    init(model: SessionModel) {
        self.model = model
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        alpha = 0.01
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }

    /// iOS can take focus away by itself, such as when an alert appears. Keep the keyboard button in step.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, model.isKeyboardActive { model.isKeyboardActive = false }
        return resigned
    }

    // MARK: On-screen keyboard

    var hasText: Bool { true }

    func insertText(_ text: String) {
        model.typeText(text)
    }

    func deleteBackward() {
        model.press(.delete)
    }

    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
    var smartDashesType: UITextSmartDashesType { get { .no } set {} }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { get { .no } set {} }
    var inlinePredictionType: UITextInlinePredictionType { get { .no } set {} }
    var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }
    var keyboardAppearance: UIKeyboardAppearance { get { .dark } set {} }

    // MARK: Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = send(presses, down: true)
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = send(presses, down: false)
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = send(presses, down: false)
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    /// Sends hardware key presses to the Mac and returns the ones it couldn't map.
    /// The screen view uses this too, so a hardware keyboard works while the on-screen one is hidden.
    func send(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let key = press.key, let code = Self.keyCode(for: key) {
                down ? model.keyDown(code) : model.keyUp(code)
            } else {
                unhandled.insert(press)
            }
        }
        return unhandled
    }

    /// Maps by physical key position so modifiers and shortcuts behave like on the Mac.
    private static func keyCode(for key: UIKey) -> VNCKeyCode? {
        let usage = key.keyCode
        if let special = specialKeys[usage] { return special }

        let raw = usage.rawValue
        // Letters a–z
        if (UIKeyboardHIDUsage.keyboardA.rawValue...UIKeyboardHIDUsage.keyboardZ.rawValue).contains(raw) {
            return VNCKeyCode(asciiCharacter: UInt8(97 + raw - UIKeyboardHIDUsage.keyboardA.rawValue))
        }
        // Digits 1–9, then 0
        if (UIKeyboardHIDUsage.keyboard1.rawValue...UIKeyboardHIDUsage.keyboard9.rawValue).contains(raw) {
            return VNCKeyCode(asciiCharacter: UInt8(49 + raw - UIKeyboardHIDUsage.keyboard1.rawValue))
        }
        if let symbol = symbolKeys[usage] {
            return VNCKeyCode(asciiCharacter: symbol.asciiValue!)
        }
        // Anything else: fall back to the unmodified character.
        if let scalar = key.charactersIgnoringModifiers.unicodeScalars.first, key.charactersIgnoringModifiers.unicodeScalars.count == 1 {
            return VNCKeyCode(scalar.value)
        }
        return nil
    }

    private static let symbolKeys: [UIKeyboardHIDUsage: Character] = [
        .keyboard0: "0", .keyboardHyphen: "-", .keyboardEqualSign: "=",
        .keyboardOpenBracket: "[", .keyboardCloseBracket: "]", .keyboardBackslash: "\\",
        .keyboardSemicolon: ";", .keyboardQuote: "'", .keyboardGraveAccentAndTilde: "`",
        .keyboardComma: ",", .keyboardPeriod: ".", .keyboardSlash: "/", .keyboardSpacebar: " ",
    ]

    private static let specialKeys: [UIKeyboardHIDUsage: VNCKeyCode] = [
        .keyboardLeftShift: .shift, .keyboardRightShift: .rightShift,
        .keyboardLeftControl: .control, .keyboardRightControl: .rightControl,
        .keyboardLeftAlt: .option, .keyboardRightAlt: .rightOption,
        .keyboardLeftGUI: .command, .keyboardRightGUI: .rightCommand,
        .keyboardReturnOrEnter: .return, .keyboardDeleteOrBackspace: .delete,
        .keyboardDeleteForward: .forwardDelete, .keyboardTab: .tab, .keyboardEscape: .escape,
        .keyboardLeftArrow: .leftArrow, .keyboardRightArrow: .rightArrow,
        .keyboardUpArrow: .upArrow, .keyboardDownArrow: .downArrow,
        .keyboardPageUp: .pageUp, .keyboardPageDown: .pageDown,
        .keyboardHome: .home, .keyboardEnd: .end,
        .keyboardF1: .f1, .keyboardF2: .f2, .keyboardF3: .f3, .keyboardF4: .f4,
        .keyboardF5: .f5, .keyboardF6: .f6, .keyboardF7: .f7, .keyboardF8: .f8,
        .keyboardF9: .f9, .keyboardF10: .f10, .keyboardF11: .f11, .keyboardF12: .f12,
    ]
}
