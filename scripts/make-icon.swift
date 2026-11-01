// Draws the 1024px app icon. Run with: bash scripts/build-icon.sh
import AppKit

let size: CGFloat = 1024
let tileInset: CGFloat = 100
let tile = CGRect(x: tileInset, y: tileInset, width: size - tileInset * 2, height: size - tileInset * 2)
let outPath = CommandLine.arguments[1]

// The same scale as BarTone.stops in Models.swift.
let scale: [(at: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
    (0, 0.20, 0.95, 0.45),
    (0.33, 1.00, 0.90, 0.15),
    (0.66, 1.00, 0.58, 0.10),
    (1, 1.00, 0.25, 0.22),
]

func color(at t: CGFloat) -> CGColor {
    let upper = scale.firstIndex { $0.at >= t } ?? scale.count - 1
    guard upper > 0 else { return CGColor(srgbRed: scale[0].r, green: scale[0].g, blue: scale[0].b, alpha: 1) }
    let a = scale[upper - 1], b = scale[upper]
    let f = (t - a.at) / (b.at - a.at)
    return CGColor(srgbRed: a.r + (b.r - a.r) * f, green: a.g + (b.g - a.g) * f, blue: a.b + (b.b - a.b) * f, alpha: 1)
}

/// Apple's icon tile is a superellipse, not a rounded rectangle.
func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let exponent: CGFloat = 5
    for step in 0..<720 {
        let angle = CGFloat(step) / 720 * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / exponent), c)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / exponent), s)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let tilePath = squircle(tile)

// Tile, with the macOS drop shadow.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
context.addPath(tilePath)
context.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()

// A little light from above, so the tile reads as a material.
let sheen = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [CGColor(gray: 1, alpha: 0.09), CGColor(gray: 1, alpha: 0)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(sheen, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])

// Ring: starts at 12 o'clock and runs clockwise, like the sidebar badges.
let center = CGPoint(x: size / 2, y: size / 2)
let radius: CGFloat = 226
let lineWidth: CGFloat = 84
let sweep: CGFloat = 0.76

context.setLineCap(.round)
context.setLineWidth(lineWidth)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
context.strokePath()

let steps = 900
for step in 0..<steps {
    let from = CGFloat(step) / CGFloat(steps)
    let to = CGFloat(step + 1) / CGFloat(steps)
    context.setStrokeColor(color(at: from))
    context.addArc(
        center: center, radius: radius,
        startAngle: .pi / 2 - from * sweep * 2 * .pi,
        endAngle: .pi / 2 - to * sweep * 2 * .pi,
        clockwise: true
    )
    context.strokePath()
}
context.restoreGState()

// Hairline edge, lit from the top.
context.saveGState()
context.addPath(tilePath)
context.setLineWidth(4)
context.replacePathWithStrokedPath()
context.clip()
let edge = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0.04)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(edge, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
context.restoreGState()

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
