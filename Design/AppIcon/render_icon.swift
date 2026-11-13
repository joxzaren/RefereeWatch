// Draws the RefereeWatch app icon: a flat silver referee whistle in a three
// quarter view on pitch green, mirrored so the mouthpiece points right and
// tilted 30 degrees so the mouthpiece points up. Everything is vector paths
// in a 1024 by 1024 design space.
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

// Flat palette: one tone per surface, no gradients on the whistle.
let grassTop = hex(0x3DA34E)
let grassBottom = hex(0x1C7431)
let sideTone = hex(0x98A1A9)        // side of the extrusion
let topTone = hex(0xC6CDD3)         // top surface of the mouthpiece
let frontTone = hex(0xE8ECEF)       // front face
let highlight = RGB(r: 1, g: 1, b: 1, a: 0.85)
let edge = hex(0x2C3236)
let slotDark = hex(0x1C2023)

/// Line width of the bold outline, in design units.
let outlineWidth: CGFloat = 14

/// Extrusion towards the back, in the whistle's own (unmirrored) drawing space:
/// up and to the right, so the top and the side show.
let depth = CGVector(dx: 84, dy: -66)

/// Placement of the whistle drawing in the icon. The drawing is mirrored around
/// its centre so the mouthpiece points right, then turned clockwise by
/// `tiltDegrees` (negative turns anticlockwise, so the mouthpiece points up), then scaled into the middle.
let whistleCentre = CGPoint(x: 539, y: 547)
let mirrored = true
let tiltDegrees: CGFloat = -30
let whistleScale: CGFloat = 1.05
/// Final nudge, in icon units, so the tilted drawing sits visually centred.
let placementShift = CGVector(dx: 52, dy: 28)

// MARK: - Shapes (top-left origin, design units, before mirroring)

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

/// Every copy of the outline from the back face to the front face. Filling them
/// all gives the solid extruded body.
func sweep() -> [CGPath] {
    let shape = outline()
    let steps = 60
    return (0...steps).map { i in
        let s = 1 - CGFloat(i) / CGFloat(steps)
        return translated(shape, CGVector(dx: depth.dx * s, dy: depth.dy * s))
    }
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
    ctx.setLineWidth(30)
    ctx.setStrokeColor(color(edge))
    ctx.strokeEllipse(in: ring)
    ctx.setLineWidth(16)
    ctx.setStrokeColor(color(sideTone))
    ctx.strokeEllipse(in: ring)
    ctx.restoreGState()
}

func drawBody(_ ctx: CGContext) {
    let copies = sweep()

    // Bold outline around the whole extruded body: stroke every copy wide,
    // then fill every copy on top, which leaves only the outer edge visible.
    ctx.setStrokeColor(color(edge))
    ctx.setLineWidth(outlineWidth * 2)
    ctx.setLineJoin(.round)
    for path in copies {
        ctx.addPath(path)
        ctx.strokePath()
    }
    ctx.setFillColor(color(sideTone))
    for path in copies {
        ctx.addPath(path)
        ctx.fillPath()
    }

    drawTop(ctx)
    drawFrontFace(ctx)
}

func drawTop(_ ctx: CGContext) {
    // Lighter flat top surface of the mouthpiece, between its front and back top edges.
    let y = mouthpiece.minY
    let frontLeft = CGPoint(x: mouthpiece.minX + 30, y: y)
    let frontRight = CGPoint(x: mouthpiece.maxX, y: y)
    let top = CGMutablePath()
    top.addLines(between: [frontLeft, frontRight, offset(frontRight, 1), offset(frontLeft, 1)])
    top.closeSubpath()
    ctx.addPath(top)
    ctx.setFillColor(color(topTone))
    ctx.fillPath()

    // The sound slot, flat dark.
    let x0: CGFloat = 455, x1: CGFloat = 565
    let slot = CGMutablePath()
    slot.addLines(between: [offset(CGPoint(x: x0, y: y), 0.22), offset(CGPoint(x: x1, y: y), 0.22),
                            offset(CGPoint(x: x1, y: y), 0.78), offset(CGPoint(x: x0, y: y), 0.78)])
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.setFillColor(color(slotDark))
    ctx.fillPath()
}

func drawFrontFace(_ ctx: CGContext) {
    let shape = outline()
    ctx.addPath(shape)
    ctx.setFillColor(color(frontTone))
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // One flat highlight along the top of the mouthpiece.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 250, y: mouthpiece.minY + 24, width: 280, height: 22),
                       cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.setFillColor(color(highlight))
    ctx.fillPath()
    // Rim of the chamber face as a single flat line.
    ctx.setStrokeColor(color(sideTone))
    ctx.setLineWidth(10)
    ctx.strokeEllipse(in: CGRect(x: chamberCenter.x - 138, y: chamberCenter.y - 138, width: 276, height: 276))
    // Mouthpiece opening.
    ctx.setFillColor(color(slotDark))
    ctx.fill(CGRect(x: mouthpiece.minX + 20, y: mouthpiece.minY + 54, width: 18, height: 52))
    ctx.restoreGState()

    // Bold outline of the front face, so it separates from the side.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(edge))
    ctx.setLineWidth(outlineWidth)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func renderIcon(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / design
    // Top-left origin, so a positive rotation turns clockwise on screen.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    drawBackground(ctx)
    ctx.translateBy(x: design / 2 + placementShift.dx, y: design / 2 + placementShift.dy)
    ctx.scaleBy(x: whistleScale, y: whistleScale)
    ctx.rotate(by: tiltDegrees * .pi / 180)
    if mirrored { ctx.scaleBy(x: -1, y: 1) }
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
    // Large versions on the right, to check nothing touches the mask edges.
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
