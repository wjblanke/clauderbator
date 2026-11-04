// Render an SVG to a transparent PNG of a given pixel width (height follows the SVG's aspect ratio).
// usage: swift svg2png.swift <input.svg> <output.png> <width px>
import AppKit

let args = CommandLine.arguments
let svg = NSImage(contentsOf: URL(fileURLWithPath: args[1]))!
let W = Int(args[3])!, H = Int((Double(W) * svg.size.height / svg.size.width).rounded())
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
svg.draw(in: NSRect(x: 0, y: 0, width: W, height: H))   // vector drawing, so edges are sharp at any size
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("\(W)x\(H) -> \(args[2])")
