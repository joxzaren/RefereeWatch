// Draws the RefereeWatch app icon: a silver referee whistle in a three quarter
// view on pitch green. Everything is vector paths in a 1024 by 1024 design space.
//
// Run from the repo root:
//   swift Design/AppIcon/render_icon.swift
//
// Writes:
//   iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png    (1024 x 1024, no alpha)
//   Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png  (same artwork)
//   Design/AppIcon/preview.png                            (masks and small sizes)

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Parameters

let design: CGFloat = 1024

/// Colours as 0...1 RGB.
struct RGB { var r, g, b: CGFloat; var a: CGFloat = 1 }
func hex(_ v: UInt32, _ a: CGFloat = 1) -> RGB {
    RGB(r: CGFloat((v >> 16) & 0xFF) / 255, g: CGFloat((v >> 8) & 0xFF) / 255, b: CGFloat(v & 0xFF) / 255, a: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ c: RGB) -> CGColor { CGColor(colorSpace: space, components: [c.r, c.g, c.b, c.a])! }
func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
    RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t)
}

let grassTop = hex(0x3DA34E)
let grassBottom = hex(0x1C7431)
let silverBack = hex(0x4E565D)      // far side of the extrusion
let silverSide = hex(0xA9B2BA)      // near side of the extrusion
let silverLight = hex(0xF8FAFB)     // lit part of the front face
let silverDark = hex(0x7D868E)      // shaded part of the front face
let edge = hex(0x434A50)
let slotDark = hex(0x1F2428)

/// Extrusion towards the back: up and to the right, so the top and the side show.
let depth = CGVector(dx: 84, dy: -66)

/// Centre of the whistle drawing (body, extrusion and ring) in design units,
/// and how much it is enlarged around the middle of the icon. At 1.1 the far
/// point of the ring stays about 0.8 of the half width from the centre, so the
/// round watch mask never cuts it.
let whistleCentre = CGPoint(x: 539, y: 547)
let whistleScale: CGFloat = 1.1

// MARK: - Shapes (top-left origin, design units)

let chamberCenter = CGPoint(x: 590, y: 585)
let chamberRadius: CGFloat = 185
let mouthpiece = CGRect(x: 210, y: chamberCenter.y - chamberRadius, width: 390, height: 140)

func outline() -> CGPath {
    let chamber = CGPath(ellipseIn: CGRect(x: chamberCenter.x - chamberRadius, y: chamberCenter.y - chamberRadius,
                                           width: chamberRadius * 2, height: chamberRadius * 2), transform: nil)
    let tube = CGPath(roundedRect: mouthpiece, cornerWidth: 34, cornerHeight: 34, transform: nil)
    return chamber.union(tube)
}

func translated(_ path: CGPath, _ v: CGVector) -> CGPath {
    var t = CGAffineTransform(translationX: v.dx, y: v.dy)
    return path.copy(using: &t)!
}

func offset(_ p: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: p.x + depth.dx * t, y: p.y + depth.dy * t)
}

// MARK: - Drawing

func drawBackground(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: space, colors: [color(grassTop), color(grassBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: design), options: [])
    // Faint mowing stripes.
    let stripe = design / 8
    ctx.setFillColor(color(RGB(r: 1, g: 1, b: 1, a: 0.045)))
    var x: CGFloat = 0
    while x < design {
        ctx.fill(CGRect(x: x, y: 0, width: stripe, height: design))
        x += stripe * 2
    }
}

func drawRing(_ ctx: CGContext) {
    // Lanyard ring on the far end of the chamber, half behind the body.
    let centre = offset(CGPoint(x: chamberCenter.x + 150, y: chamberCenter.y - 150), 0.55)
    let ring = CGRect(x: centre.x - 78, y: centre.y - 58, width: 156, height: 116)
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: -0.55)
    ctx.translateBy(x: -centre.x, y: -centre.y)
    ctx.setLineWidth(26)
    ctx.setStrokeColor(color(silverBack))
    ctx.strokeEllipse(in: ring)
    ctx.setLineWidth(12)
    ctx.setStrokeColor(color(silverSide))
    ctx.strokeEllipse(in: ring.offsetBy(dx: -3, dy: -4))
    ctx.restoreGState()
}

func drawBody(_ ctx: CGContext) {
    let shape = outline()

    // One shadow for the whole extruded body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 18, height: 30), blur: 46, color: color(RGB(r: 0, g: 0.12, b: 0.03, a: 0.55)))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // Sweep from the back face to the front face. Each copy is a little lighter,
    // which shades the top and side surfaces of the extrusion.
    let steps = 90
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let s = 1 - t
        ctx.addPath(translated(shape, CGVector(dx: depth.dx * s, dy: depth.dy * s)))
        ctx.setFillColor(color(mix(silverBack, silverSide, pow(t, 0.8))))
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Thin dark line where the top surface meets the front face, for crispness when small.
    drawSlot(ctx)
    drawFrontFace(ctx, shape)
}

func drawSlot(_ ctx: CGContext) {
    // The sound slot on top of the mouthpiece, near the chamber.
    let x0: CGFloat = 455, x1: CGFloat = 565, y = mouthpiece.minY
    let a = offset(CGPoint(x: x0, y: y), 0.22)
    let b = offset(CGPoint(x: x1, y: y), 0.22)
    let c = offset(CGPoint(x: x1, y: y), 0.78)
    let d = offset(CGPoint(x: x0, y: y), 0.78)
    let slot = CGMutablePath()
    slot.addLines(between: [a, b, c, d])
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.setFillColor(color(slotDark))
    ctx.fillPath()
    // Light lip on the near edge of the slot.
    ctx.setStrokeColor(color(RGB(r: 1, g: 1, b: 1, a: 0.55)))
    ctx.setLineWidth(5)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
}

func drawFrontFace(_ ctx: CGContext, _ shape: CGPath) {
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Metallic gradient, lit from the top left.
    let metal = CGGradient(colorsSpace: space,
                           colors: [color(silverLight), color(hex(0xD3D9DE)), color(silverDark)] as CFArray,
                           locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(metal, start: CGPoint(x: 260, y: 380), end: CGPoint(x: 720, y: 790), options: [])

    // Soft round sheen on the chamber.
    let sheen = CGGradient(colorsSpace: space,
                           colors: [color(RGB(r: 1, g: 1, b: 1, a: 0.75)), color(RGB(r: 1, g: 1, b: 1, a: 0))] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 520, y: 520), startRadius: 0,
                           endCenter: CGPoint(x: 520, y: 520), endRadius: 170, options: [])

    // Specular streak along the top of the mouthpiece.
    let streak = CGPath(roundedRect: CGRect(x: 250, y: mouthpiece.minY + 18, width: 300, height: 18),
                        cornerWidth: 9, cornerHeight: 9, transform: nil)
    ctx.addPath(streak)
    ctx.setFillColor(color(RGB(r: 1, g: 1, b: 1, a: 0.8)))
    ctx.fillPath()

    // Raised rim of the chamber face.
    ctx.setStrokeColor(color(RGB(r: 0.25, g: 0.28, b: 0.31, a: 0.28)))
    ctx.setLineWidth(8)
    ctx.strokeEllipse(in: CGRect(x: chamberCenter.x - 140, y: chamberCenter.y - 140, width: 280, height: 280))

    // Mouthpiece opening at the left end.
    ctx.setFillColor(color(slotDark))
    ctx.fill(CGRect(x: mouthpiece.minX + 18, y: mouthpiece.minY + 58, width: 14, height: 44))
    ctx.restoreGState()

    // Outline of the front face.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(edge))
    ctx.setLineWidth(7)
    ctx.strokePath()
}

func renderIcon(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / design
    // Top-left origin.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    drawBackground(ctx)
    ctx.translateBy(x: design / 2, y: design / 2)
    ctx.scaleBy(x: whistleScale, y: whistleScale)
    ctx.translateBy(x: -whistleCentre.x, y: -whistleCentre.y)
    drawRing(ctx)
    drawBody(ctx)
    return ctx.makeImage()!
}

// MARK: - Preview sheet

func drawText(_ ctx: CGContext, _ text: String, at p: CGPoint, size: CGFloat, color c: RGB) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(c),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

func renderPreview(_ icon: CGImage) -> CGImage {
    let width = 1560, height = 760
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    // Light half and dark half, like the home screen in light and dark mode.
    ctx.setFillColor(color(hex(0xEEF0F2)))
    ctx.fill(CGRect(x: 0, y: 380, width: width, height: 380))
    ctx.setFillColor(color(hex(0x111315)))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: 380))

    // Pixel sizes: iPhone home 60pt@3x and @2x, Settings 29pt@3x and @2x.
    // Watch grid at roughly 100, 88 and 80 px (the 40pt watch size at 2x).
    let phone: [(Int, String)] = [(180, "60pt @3x"), (120, "60pt @2x"), (87, "29pt @3x"), (58, "29pt @2x")]
    let watch: [(Int, String)] = [(100, "watch 50pt @2x"), (88, "watch 44pt @2x"), (80, "watch 40pt @2x")]

    for (rowY, textColor) in [(CGFloat(430), hex(0x333A40)), (CGFloat(50), hex(0xC9CED3))] {
        var x: CGFloat = 40
        for (px, label) in phone {
            let s = CGFloat(px)
            let r = CGRect(x: x, y: rowY + 60, width: s, height: s)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.2237, cornerHeight: s * 0.2237, transform: nil))
            ctx.clip()
            ctx.draw(icon, in: r)
            ctx.restoreGState()
            drawText(ctx, label, at: CGPoint(x: x, y: rowY + 30), size: 16, color: textColor)
            x += s + 50
        }
        x += 30
        for (px, label) in watch {
            let s = CGFloat(px)
            let r = CGRect(x: x, y: rowY + 60, width: s, height: s)
            ctx.saveGState()
            ctx.addEllipse(in: r)
            ctx.clip()
            ctx.draw(icon, in: r)
            ctx.restoreGState()
            drawText(ctx, label, at: CGPoint(x: x, y: rowY + 30), size: 16, color: textColor)
            x += s + 60
        }
    }
    // Large circle mask on the right, to check nothing touches the watch edge.
    let big = CGRect(x: 1270, y: 420, width: 260, height: 260)
    ctx.saveGState(); ctx.addEllipse(in: big); ctx.clip(); ctx.draw(icon, in: big); ctx.restoreGState()
    let bigPhone = CGRect(x: 1270, y: 60, width: 260, height: 260)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bigPhone, cornerWidth: 260 * 0.2237, cornerHeight: 260 * 0.2237, transform: nil))
    ctx.clip(); ctx.draw(icon, in: bigPhone); ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = here.deletingLastPathComponent().deletingLastPathComponent()
let icon = renderIcon(size: 1024)
writePNG(icon, to: root.appendingPathComponent("iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
writePNG(icon, to: root.appendingPathComponent("Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
writePNG(renderPreview(icon), to: here.appendingPathComponent("preview.png"))
