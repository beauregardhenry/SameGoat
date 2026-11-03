// Turns the raw App Store screenshots into captioned marketing images: the goat and a headline on
// Same Goat teal, with the screenshot below in a rounded frame. Run take-screenshots.sh first, then:
//
//   swift scripts/make-marketing-shots.swift
//
// Writes docs/app-store/screenshots/marketing/<device>/<name>.png at the sizes App Store Connect wants.
import AppKit
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let shots = root.appendingPathComponent("docs/app-store/screenshots")
let goatURL = root.appendingPathComponent("docs/brand/goat-cheer.svg")

let captions: [(name: String, headline: String, line: String)] = [
    // Line breaks are set by hand so no headline ends on a single word.
    ("1-kid-chores", "Chores kids actually\nwant to finish", "The goat cheers them on, all the way to their reward."),
    ("2-kid-rewards", "Points add up to\nrewards they choose", "Movie night, ice cream, or real pocket money."),
    ("3-family-board", "Everyone's day\non one board", "Made for the kitchen tablet."),
    ("4-parent-chores", "Fair points\nfor every chore", "Suggested from how long it takes and how hard it is."),
    ("5-parent-review", "Approve\nwith one tap", "Less nagging, more high-fives."),
]

/// Canvas size, the screenshot's width and top edge, and the text sizes, per device.
struct Layout { let width, height, shotWidth, shotTop, headline, line, goat, corner: CGFloat }
let layouts: [(folder: String, layout: Layout)] = [
    ("iphone-6.9", Layout(width: 1320, height: 2868, shotWidth: 1090, shotTop: 760, headline: 96, line: 48, goat: 150, corner: 120)),
    ("ipad-13", Layout(width: 2064, height: 2752, shotWidth: 1640, shotTop: 760, headline: 104, line: 52, goat: 150, corner: 60)),
]

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func draw(_ text: String, font: NSFont, color: NSColor, in rect: CGRect) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        .draw(with: rect, options: [.usesLineFragmentOrigin])
}

func render(_ shot: NSImage, caption: (name: String, headline: String, line: String), layout l: Layout, goat: NSImage?) -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: Int(l.width), height: Int(l.height), bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    // Draw top-down, like the layout numbers read.
    cg.translateBy(x: 0, y: l.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let top = NSColor(srgbRed: 0.36, green: 0.77, blue: 0.83, alpha: 1)
    let bottom = NSColor(srgbRed: 0.17, green: 0.55, blue: 0.63, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: CGRect(x: 0, y: 0, width: l.width, height: l.height), angle: 90)

    var y: CGFloat = 90
    if let goat {
        let size = CGSize(width: l.goat * 1.4, height: l.goat * 1.4 * goat.size.height / goat.size.width)
        goat.draw(in: CGRect(x: (l.width - size.width) / 2, y: y, width: size.width, height: size.height))
        y += size.height + 10
    }
    let side: CGFloat = l.width * 0.08
    draw(caption.headline, font: rounded(l.headline, .heavy), color: .white,
         in: CGRect(x: side, y: y, width: l.width - side * 2, height: l.headline * 2.6))
    let headlineHeight = NSAttributedString(string: caption.headline, attributes: [.font: rounded(l.headline, .heavy)])
        .boundingRect(with: CGSize(width: l.width - side * 2, height: 1000), options: [.usesLineFragmentOrigin]).height
    draw(caption.line, font: rounded(l.line, .medium), color: NSColor.white.withAlphaComponent(0.88),
         in: CGRect(x: side, y: y + headlineHeight + 14, width: l.width - side * 2, height: l.line * 2.8))

    // The screenshot in a dark rounded frame, running off the bottom edge.
    let shotHeight = l.shotWidth * shot.size.height / shot.size.width
    let frame = CGRect(x: (l.width - l.shotWidth) / 2, y: l.shotTop, width: l.shotWidth, height: shotHeight)
    let bezel: CGFloat = 18
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), xRadius: l.corner + bezel, yRadius: l.corner + bezel).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: l.corner, yRadius: l.corner).addClip()
    shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
}

let goat = NSImage(contentsOf: goatURL)
var made = 0
for (folder, layout) in layouts {
    let out = shots.appendingPathComponent("marketing/\(folder)")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for caption in captions {
        let source = shots.appendingPathComponent("\(folder)/\(caption.name).png")
        guard let shot = NSImage(contentsOf: source) else {
            FileHandle.standardError.write("Missing \(source.path). Run scripts/take-screenshots.sh first.\n".data(using: .utf8) ?? Data())
            exit(1)
        }
        guard let png = render(shot, caption: caption, layout: layout, goat: goat) else { exit(1) }
        try png.write(to: out.appendingPathComponent("\(caption.name).png"))
        made += 1
    }
}
print("Made \(made) marketing images in \(shots.path)/marketing")
