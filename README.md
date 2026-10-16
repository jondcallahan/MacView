# MacView

An iPhone and iPad app for seeing and controlling your Mac's screen over VNC (macOS Screen Sharing). Built with SwiftUI, Liquid Glass and [RoyalVNCKit](https://github.com/royalapplications/royalvnc).

## Features

- **Look around:** drag to pan, pinch or double-tap to zoom. Nothing is sent to the Mac.
- **Mouse:** use the screen like a trackpad. Drag to move the pointer, tap to click, tap with two fingers to right-click, drag with two fingers to scroll, and touch and hold then drag to select. On iPad, a connected trackpad or mouse controls the pointer directly.
- **Keyboard:** the on-screen keyboard, plus a row with esc, tab, ⌃ ⌥ ⌘ ⇧ and arrow keys. Hardware keyboards send shortcuts like ⌘C to the Mac.
- **Finds your Macs:** Macs with Screen Sharing on show up by themselves when you're on the same network.
- **Home and away:** give each Mac a local address and a Tailscale (or other VPN) address. MacView tries the local one first and falls back to Tailscale, so it's the same Mac in the list wherever you are.
- Sign in with your Mac account. Passwords are stored in the iOS Keychain on this device only.

## Set up your Mac

On the Mac, open System Settings > General > Sharing and turn on **Screen Sharing**.

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`, then add your Apple Developer team ID and a bundle ID prefix. This file is git-ignored.
2. Run `xcodegen generate`.
3. Open `MacView.xcodeproj` and run on your device.

## Security

When you sign in, your Mac password is encrypted on its way to the Mac. After that, standard VNC doesn't encrypt the session, so the screen and your keystrokes travel unencrypted, and VNC can't confirm that you've reached your own Mac. That's fine on your home network. From anywhere else, connect over a VPN such as Tailscale, and don't expose port 5900 to the internet.

MacView collects no data. See the [privacy policy](PRIVACY.md).

## Known limits

- Clipboard sync is off.
- iOS keeps some shortcuts for itself, such as ⌘Tab and ⌘Space.
