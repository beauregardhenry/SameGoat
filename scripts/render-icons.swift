// Renders an SVG to a PNG: swift scripts/render-icons.swift in.svg out.png 1024 [opaque]
// The size can also be WIDTHxHEIGHT, such as 1600x480.
// Uses the system's SVG support in AppKit, so nothing needs installing.
// "opaque" drops the alpha channel, which App Store icons need.
import AppKit
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
    exit(1)
}

let args = CommandLine.arguments
let dims = args.count >= 4 ? args[3].split(separator: "x").compactMap { Int($0) } : []
guard dims.count == 1 || dims.count == 2 else { fail("usage: render-icons.swift in.svg out.png size [opaque]") }
let width = dims[0], height = dims.last ?? dims[0]
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else { fail("Couldn't read \(args[1])") }
let opaque = args.count > 4 && args[4] == "opaque"

let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: alpha.rawValue) else { fail("Couldn't make a drawing context") }
context.interpolationQuality = .high
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()

guard let cgImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else { fail("Couldn't write \(args[2])") }
CGImageDestinationAddImage(destination, cgImage, nil)
guard CGImageDestinationFinalize(destination) else { fail("Couldn't write \(args[2])") }
