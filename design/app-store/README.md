# App Store screenshots

`screenshots/` holds the finished images: iPhone 6.9" (1320×2868), iPad 13" (2752×2064) and Apple Vision Pro (3840×2160).

To make them again:

1. Render the mock Mac desktop and convert it to raw pixels:
   `swift source/snap.swift source/desktop.html desktop4x.png 1280 800`, then
   `sips -z 1600 2560 desktop4x.png --out desktop.png` and `swift source/raw.swift desktop.png source/desktop.rgbx`.
2. Serve it: `python3 source/imgserver.py 5998`. Give it a tidy name with
   `dns-sd -P "MacBook Pro" _rfb._tcp local 5998 macbook-pro.local 127.0.0.1`.
3. Load `source/hosts.json` into the simulator's saved Macs:
   `xcrun simctl spawn <device> defaults write com.joncallahan.ScreenDoor hosts -data <hex of the JSON>`.
   Hide the Macs Bonjour finds on your own network so they don't appear in the shots.
4. Capture with `xcrun simctl io <device> screenshot`, after
   `xcrun simctl status_bar <device> override --time 9:41`.
5. Add the captions: `swiftc -O source/compose.swift -o compose`, then
   `./compose <width> <height> raw.png out.png "Title" "Subtitle" <screenshot width fraction> <corner radius>`.
