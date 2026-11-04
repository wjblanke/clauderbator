// Enlarge a photo to poster size and split it into overlapping printable pieces.
// usage: [POSTER_W=in POSTER_H=in] swift enlarge.swift <input image> <output> [jpeg]
//   default: <output> is a Letter-size PDF (0.25" margins)
//   jpeg:    <output> is a folder of 4x6" photos at 300 dpi
import Foundation
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let jpegMode = args.dropFirst(3).contains("jpeg")
let env = ProcessInfo.processInfo.environment     // poster size in inches, overridable via POSTER_W / POSTER_H
let POSTER_W = Double(env["POSTER_W"] ?? "") ?? 15.16, POSTER_H = Double(env["POSTER_H"] ?? "") ?? 18.95
let DPI = 300.0, OV = 0.5                       // print resolution, overlap between neighbouring pieces (inches)
let PAGE_W = 8.5, PAGE_H = 11.0, M = 0.25       // letter, 0.25" margins (PDF mode)

// --- enlarge: Lanczos resampling to 300 dpi, then a mild unsharp mask to restore edge crispness
let src = CIImage(contentsOf: input, options: [.applyOrientationProperty: true])!
let BW = Int((POSTER_W * DPI).rounded()), BH = Int((POSTER_H * DPI).rounded())
let sx = Double(BW) / src.extent.width, sy = Double(BH) / src.extent.height
let lanczos = CIFilter(name: "CILanczosScaleTransform")!
lanczos.setValue(src.clampedToExtent(), forKey: kCIInputImageKey)   // clamp so edges don't fade to transparent
lanczos.setValue(sy, forKey: kCIInputScaleKey)
lanczos.setValue(sx / sy, forKey: kCIInputAspectRatioKey)
let unsharp = CIFilter(name: "CIUnsharpMask")!
unsharp.setValue(lanczos.outputImage!, forKey: kCIInputImageKey)
unsharp.setValue(2.0, forKey: kCIInputRadiusKey)
unsharp.setValue(0.4, forKey: kCIInputIntensityKey)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
let master = ci.createCGImage(unsharp.outputImage!, from: CGRect(x: 0, y: 0, width: BW, height: BH))!

// --- tiling
func layout(_ tw: Double, _ th: Double) -> (cols: Int, rows: Int) {
    (1 + max(0, Int(ceil((POSTER_W - tw) / (tw - OV)))), 1 + max(0, Int(ceil((POSTER_H - th) / (th - OV)))))
}
let px = { (inches: Double) in Int((inches * DPI).rounded()) }

// One piece of the poster: the artwork at poster pixel (X0, Y0) of size cw x chh, placed top-left on a white
// canvas of TPW x TPH. Dashed lines mark the overlap strip on the right/bottom edges only: those strips get
// covered by the next piece, so the lines never show on the finished poster.
func tile(X0: Int, Y0: Int, cw: Int, chh: Int, TPW: Int, TPH: Int, right: Bool, bottom: Bool) -> CGImage {
    let g = CGContext(data: nil, width: TPW, height: TPH, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    g.setFillColor(gray: 1, alpha: 1); g.fill(CGRect(x: 0, y: 0, width: TPW, height: TPH))
    let part = master.cropping(to: CGRect(x: X0, y: Y0, width: cw, height: chh))!   // top-left origin
    let top = Double(TPH)                                                           // context is bottom-left origin
    g.draw(part, in: CGRect(x: 0, y: top - Double(chh), width: Double(cw), height: Double(chh)))
    g.setStrokeColor(gray: 0.5, alpha: 1); g.setLineWidth(3); g.setLineDash(phase: 0, lengths: [30, 30])
    let o = Double(px(OV))
    if right  { g.move(to: CGPoint(x: Double(cw) - o, y: top - Double(chh))); g.addLine(to: CGPoint(x: Double(cw) - o, y: top)) }
    if bottom { g.move(to: CGPoint(x: 0, y: top - Double(chh) + o)); g.addLine(to: CGPoint(x: Double(cw), y: top - Double(chh) + o)) }
    g.strokePath()
    return g.makeImage()!
}

func jpegData(_ img: CGImage) -> Data {
    let data = NSMutableData()
    let d = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.92,
                                        kCGImagePropertyDPIWidth: DPI, kCGImagePropertyDPIHeight: DPI] as CFDictionary)
    CGImageDestinationFinalize(d)
    return data as Data
}

if jpegMode {
    // portrait or landscape photos, whichever needs fewer prints
    let (TW, TH) = [(4.0, 6.0), (6.0, 4.0)].min { layout($0.0, $0.1).cols * layout($0.0, $0.1).rows <
                                                   layout($1.0, $1.1).cols * layout($1.0, $1.1).rows }!
    let (cols, rows) = layout(TW, TH)
    let TPW = px(TW), TPH = px(TH)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for pr in 0..<rows { for pc in 0..<cols {
        let X0 = px(Double(pc) * (TW - OV)), Y0 = px(Double(pr) * (TH - OV))
        let img = tile(X0: X0, Y0: Y0, cw: min(TPW, BW - X0), chh: min(TPH, BH - Y0), TPW: TPW, TPH: TPH,
                       right: pc < cols - 1, bottom: pr < rows - 1)
        try jpegData(img).write(to: out.appendingPathComponent("row\(pr + 1)_col\(pc + 1).jpg"))
    } }
    print("\(BW)x\(BH) px poster, \(rows) rows x \(cols) cols = \(rows * cols) photos of \(TW)x\(TH) in -> \(out.path)")
} else {
    let PW = PAGE_W - 2 * M, PH = PAGE_H - 2 * M
    let (cols, rows) = layout(PW, PH)
    var box = CGRect(x: 0, y: 0, width: PAGE_W * 72, height: PAGE_H * 72)
    let pdf = CGContext(out as CFURL, mediaBox: &box, nil)!
    for pr in 0..<rows { for pc in 0..<cols {
        let X0 = px(Double(pc) * (PW - OV)), Y0 = px(Double(pr) * (PH - OV))
        let cw = min(px(PW), BW - X0), chh = min(px(PH), BH - Y0)
        // re-load from JPEG data so the PDF stores the piece JPEG-compressed rather than as raw pixels
        let jpg = jpegData(tile(X0: X0, Y0: Y0, cw: cw, chh: chh, TPW: cw, TPH: chh, right: pc < cols - 1, bottom: pr < rows - 1))
        let img = CGImage(jpegDataProviderSource: CGDataProvider(data: jpg as CFData)!, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent)!
        let w = Double(cw) / DPI * 72, h = Double(chh) / DPI * 72
        let r = CGRect(x: M * 72, y: (PAGE_H - M) * 72 - h, width: w, height: h)
        pdf.beginPDFPage(nil)
        pdf.draw(img, in: r)
        pdf.setStrokeColor(gray: 0.6, alpha: 1); pdf.setLineWidth(0.3); pdf.stroke(r)   // thin grey trim guide
        let label = "Row \(pr + 1) Col \(pc + 1)  (page \(pr * cols + pc + 1) of \(rows * cols))  - poster \(POSTER_W) x \(POSTER_H) in"
            + " - lay the next page's edge on the dashed line (\(OV) in overlap)"
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 7, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.5, alpha: 1)]))
        pdf.textPosition = CGPoint(x: M * 72, y: M * 72 / 2 - 2)
        CTLineDraw(line, pdf)
        pdf.endPDFPage()
    } }
    pdf.closePDF()
    print("\(BW)x\(BH) px poster, \(rows) rows x \(cols) cols = \(rows * cols) letter pages -> \(out.path)")
}
