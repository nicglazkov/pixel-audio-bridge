import AppKit
import ImageIO
import UniformTypeIdentifiers

// Renders AppIcon.iconset. The glyph is hand-drawn rather than an SF Symbol,
// because Apple's SF Symbols license disallows their use in app icons.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"

/// Draw the icon into a y-up context of edge length `s`.
func draw(in ctx: CGContext, s: CGFloat) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // --- rounded-square plate -------------------------------------------------
    // macOS icons sit inset from the canvas edge; ~5.5% reads correctly in the
    // Dock alongside system icons.
    let inset = s * 0.055
    let plate = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = plate.width * 0.2237      // approximates Apple's squircle
    let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [0.42, 0.29, 0.96, 1.0])!,   // indigo
            CGColor(colorSpace: space, components: [0.13, 0.52, 0.96, 1.0])!    // azure
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: plate.minX, y: plate.maxY),
                           end:   CGPoint(x: plate.maxX, y: plate.minY),
                           options: [])

    // Soft highlight across the top so the plate does not read as flat.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [1, 1, 1, 0.22])!,
            CGColor(colorSpace: space, components: [1, 1, 1, 0.0])!
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: plate.midX, y: plate.maxY),
                           end:   CGPoint(x: plate.midX, y: plate.midY),
                           options: [])
    ctx.restoreGState()

    // --- headphones -----------------------------------------------------------
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.setLineCap(.round)

    let cx = s * 0.5
    let bandY = s * 0.505
    let bandR = s * 0.208
    let band = s * 0.072

    ctx.setLineWidth(band)
    ctx.addArc(center: CGPoint(x: cx, y: bandY), radius: bandR,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Ear cups, hanging from each end of the band.
    let cupW = s * 0.132
    let cupH = s * 0.225
    let cupY = bandY - cupH + s * 0.020
    let cupR = cupW * 0.5

    for dx in [-bandR, bandR] {
        let cup = CGRect(x: cx + dx - cupW / 2, y: cupY, width: cupW, height: cupH)
        ctx.addPath(CGPath(roundedRect: cup, cornerWidth: cupR, cornerHeight: cupR, transform: nil))
        ctx.fillPath()
    }

    // --- signal arcs ----------------------------------------------------------
    // Three ascending arcs read as "audio arriving over the air" and keep the
    // mark from being just a generic headphones glyph.
    ctx.setLineCap(.round)
    // Outer radius is capped so the arc tips clear the ear cups, whose inner
    // edges sit at (bandR - cupW/2) from centre.
    let arcCenter = CGPoint(x: cx, y: s * 0.285)
    for (i, r) in [s * 0.072, s * 0.121, s * 0.170].enumerated() {
        ctx.setLineWidth(s * 0.030)
        ctx.setStrokeColor(CGColor(colorSpace: space,
                                   components: [1, 1, 1, 0.95 - Double(i) * 0.22])!)
        ctx.addArc(center: arcCenter, radius: r,
                   startAngle: .pi * 0.22, endAngle: .pi * 0.78, clockwise: false)
        ctx.strokePath()
    }
}

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil,
                              width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    draw(in: ctx, s: s)
    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not create \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// iconutil expects this exact set of names.
let variants: [(name: String, px: Int)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",    32),
    ("icon_32x32",      32),  ("icon_32x32@2x",    64),
    ("icon_128x128",   128),  ("icon_128x128@2x", 256),
    ("icon_256x256",   256),  ("icon_256x256@2x", 512),
    ("icon_512x512",   512),  ("icon_512x512@2x",1024),
]

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for v in variants {
    guard let img = render(size: v.px) else { fatalError("render failed at \(v.px)") }
    write(img, to: "\(outDir)/\(v.name).png")
}

// Standalone preview for eyeballing the result.
if let img = render(size: 512) {
    write(img, to: "\(outDir)/../icon-preview.png")
}
print("wrote \(variants.count) icon variants to \(outDir)")
