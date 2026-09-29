// Draws the NimbleTask app icon (concept: "a ticked box") following the
// Nimble Icons style guide, and writes the 1024×1024 master PNG.
//
//   swift scripts/generate_icon.swift <output.png>
//
// Colors are the style guide's sRGB values, set explicitly in sRGB so the PNG
// pixels are exactly these hex codes (see style guide v2, "Color").

import AppKit
import CoreGraphics

let nimbleBlue = CGColor(srgbRed: 0x00/255, green: 0x9A/255, blue: 0xD6/255, alpha: 1)  // #009AD6
let deepBlue   = CGColor(srgbRed: 0x00/255, green: 0x6C/255, blue: 0xA5/255, alpha: 1)  // #006CA5
let cream      = CGColor(srgbRed: 0xFA/255, green: 0xF8/255, blue: 0xF4/255, alpha: 1)  // #FAF8F4

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Background: diagonal gradient, Nimble Blue (top-left) → Deep Blue (bottom-right).
// CG's origin is bottom-left, so top-left is (0, size).
let s = CGFloat(size)
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [nimbleBlue, deepBlue] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Work on a 512 grid with a top-left origin, scaled ×2 onto the canvas.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 2, y: -2)

// Box: 312×312 (61% of the width), corner radius 88 (28% of its side).
let box = CGRect(x: 100, y: 100, width: 312, height: 312)
ctx.setFillColor(cream)
ctx.addPath(CGPath(roundedRect: box, cornerWidth: 88, cornerHeight: 88, transform: nil))
ctx.fillPath()

// Tick, cut into the box in Nimble Blue. 48 wide on the grid (96 px), like
// Nimble Bot's dots, so it survives at 16×16.
ctx.setStrokeColor(nimbleBlue)
ctx.setLineWidth(48)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addLines(between: [CGPoint(x: 174, y: 262), CGPoint(x: 232, y: 320), CGPoint(x: 342, y: 194)])
ctx.strokePath()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
