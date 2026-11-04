// Trim a transparent-background logo to its visible pixels, scale it to an exact printed width and centre it
// on a solid-colour photo, saved as a 300 dpi JPEG.
// usage: swift place_logo.swift <logo.png> <out.jpg> <logo width in> <photo width in> <photo height in>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let DPI = 300.0, ALPHA_MIN: UInt8 = 8          // pixels fainter than ~3% opacity don't count toward the logo's width
let logoW = Double(args[3])!, photoW = Double(args[4])!, photoH = Double(args[5])!

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// find the bounding box of visible pixels
let buf = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
buf.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = buf.data!.assumingMemoryBound(to: UInt8.self)
var minX = w, maxX = -1, minY = h, maxY = -1                      // rows counted from the top
for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= ALPHA_MIN {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let crop = img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

// scale to the requested width and centre on a black photo
let PW = Int((photoW * DPI).rounded()), PH = Int((photoH * DPI).rounded())
let dw = logoW * DPI, dh = dw * Double(crop.height) / Double(crop.width)
let out = CGContext(data: nil, width: PW, height: PH, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
out.setFillColor(gray: 0, alpha: 1); out.fill(CGRect(x: 0, y: 0, width: PW, height: PH))
out.interpolationQuality = .high
out.draw(crop, in: CGRect(x: (Double(PW) - dw) / 2, y: (Double(PH) - dh) / 2, width: dw, height: dh))

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.95,
                                                    kCGImagePropertyDPIWidth: DPI, kCGImagePropertyDPIHeight: DPI] as CFDictionary)
CGImageDestinationFinalize(dest)
print("logo trimmed to \(crop.width)x\(crop.height) px -> printed \(logoW) x \(String(format: "%.2f", dh / DPI)) in "
      + "on a \(photoW) x \(photoH) in photo (\(PW)x\(PH) px @ \(Int(DPI)) dpi); "
      + "side border \(String(format: "%.2f", (photoW - logoW) / 2)) in, top/bottom \(String(format: "%.2f", (photoH - dh / DPI) / 2)) in")
