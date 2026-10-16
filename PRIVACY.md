# MacView privacy policy

Effective October 16, 2026

MacView connects your iPhone or iPad directly to your own Macs. It has no account and no servers, and it doesn't collect, share or sell any information about you. The developer receives nothing from the app: no analytics, no crash reports and no tracking.

## What stays on your device

- **Your list of Macs:** each Mac's name, local and Tailscale addresses, port and username. These are kept in the app's own storage on your device, and are included in your device backups like other app settings.
- **Your Mac passwords:** stored in the iOS Keychain, readable only while your device is unlocked. They stay on this device, so they never sync to iCloud and aren't moved to a new device.

Deleting a Mac from the list deletes its saved password. Deleting MacView deletes your list of Macs, but iOS may keep the saved passwords in the Keychain. MacView removes them the next time you add a Mac after reinstalling. To remove them right away, delete your Macs in MacView before you delete the app.

## What MacView sends, and where

- **To your Macs only:** when you connect, MacView talks directly to the Mac you chose, on your local network or through your own VPN, such as Tailscale. Your sign-in, the Mac's screen, and your taps, clicks and typing go only between your device and that Mac. MacView doesn't save the screen or what you type.
- **On your local network:** to list nearby Macs, MacView looks for Macs that have Screen Sharing turned on, using Bonjour. iOS asks for your permission first.

## Security

When you sign in, your password is encrypted on its way to the Mac. After that, VNC doesn't encrypt the session, and it can't confirm that you've reached your own Mac. On a network you don't trust, connect through Tailscale or another VPN.

If a Mac has both a local and a Tailscale address, MacView uses the local one whenever something answers there. To always connect through Tailscale, leave the Mac's Local address empty.

## Questions

MacView is open source at [github.com/jondcallahan/MacView](https://github.com/jondcallahan/MacView). Ask questions or report problems in its [issues](https://github.com/jondcallahan/MacView/issues). If this policy changes, the new version will be published here with a new effective date.
