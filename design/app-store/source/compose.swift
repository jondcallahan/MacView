import AppKit
// Lays out an App Store image: a caption on the blue icon gradient, with the screenshot below.
// Usage: compose canvasW canvasH screenshot.png out.png "Title" "Subtitle" shotWidthFraction cornerRadius
let a = CommandLine.arguments
let W = CGFloat(Double(a[1])!), H = CGFloat(Double(a[2])!)
let shot = NSImage(contentsOfFile: a[3])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let title = a[5], subtitle = a[6]
let fraction = CGFloat(Double(a[7])!), radius = CGFloat(Double(a[8])!)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ al: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: al) }
// Background: the icon's gradient, top light to bottom deep.
let grad = CGGradient(colorsSpace: space, colors: [rgb(75, 177, 255), rgb(11, 93, 243)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
// A faint mesh, echoing the icon.
let pitch = W / 44
ctx.setStrokeColor(rgb(255, 255, 255, 0.06)); ctx.setLineWidth(pitch * 0.18)
var x: CGFloat = 0; while x < W { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)); x += pitch }
var y: CGFloat = 0; while y < H { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); y += pitch }
ctx.strokePath()

// Text, centred near the top.
let base = min(W, H * 0.75)
func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, top: CGFloat, maxWidth: CGFloat) -> CGFloat {
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineHeightMultiple = 1.05
    let attr = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: para])
    let setter = CTFramesetterCreateWithAttributedString(attr)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
    let rect = CGRect(x: (W - maxWidth) / 2, y: H - top - fit.height, width: maxWidth, height: ceil(fit.height))
    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
    return top + fit.height
}
let titleTop = H * 0.055
let afterTitle = draw(title, size: base * 0.085, weight: .bold, alpha: 1, top: titleTop, maxWidth: W * 0.86)
let afterSub = draw(subtitle, size: base * 0.04, weight: .medium, alpha: 0.9, top: afterTitle + base * 0.02, maxWidth: W * 0.8)

// Screenshot, centred below the text, bleeding off the bottom if it's tall.
let sw = W * fraction, sh = sw * CGFloat(shot.height) / CGFloat(shot.width)
let top = afterSub + base * 0.05
let rect = CGRect(x: (W - sw) / 2, y: H - top - sh, width: sw, height: sh)
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -base * 0.01), blur: base * 0.05, color: rgb(0, 20, 80, 0.45))
ctx.addPath(path); ctx.setFillColor(.black); ctx.fillPath(); ctx.restoreGState()
ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.interpolationQuality = .high; ctx.draw(shot, in: rect); ctx.restoreGState()
ctx.addPath(path); ctx.setStrokeColor(rgb(255, 255, 255, 0.25)); ctx.setLineWidth(base * 0.003); ctx.strokePath()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[4]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
