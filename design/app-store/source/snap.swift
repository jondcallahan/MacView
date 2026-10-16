import AppKit
import WebKit
// Renders an HTML file to a PNG at 2x. Usage: snap in.html out.png width height
let a = CommandLine.arguments
let w = CGFloat(Double(a[3])!), h = CGFloat(Double(a[4])!)
let app = NSApplication.shared
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h))
win.contentView = web
final class D: NSObject, WKNavigationDelegate {
    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let c = WKSnapshotConfiguration(); c.snapshotWidth = NSNumber(value: Double(w) * 2)
            v.takeSnapshot(with: c) { img, err in
                guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { print(err as Any); exit(1) }
                try! png.write(to: URL(fileURLWithPath: a[2])); exit(0)
            }
        }
    }
}
let d = D(); web.navigationDelegate = d
web.loadFileURL(URL(fileURLWithPath: a[1]), allowingReadAccessTo: URL(fileURLWithPath: a[1]).deletingLastPathComponent())
app.run()
