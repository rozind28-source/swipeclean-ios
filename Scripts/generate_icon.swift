import Foundation
import CoreGraphics
import AppKit

// Determine project root directory
let fileManager = FileManager.default
let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)

// Path to AppIcon asset catalog
let iconsetURL = currentDirectory.appendingPathComponent("Sources/Resources/Assets.xcassets/AppIcon.appiconset")
let outputImageURL = iconsetURL.appendingPathComponent("AppIcon-1024.png")
let contentsJsonURL = iconsetURL.appendingPathComponent("Contents.json")

// Ensure directory exists
try? fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let width = 1024
let height = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ Error: Failed to create CGContext")
    exit(1)
}

// 1. Draw Background Gradient (#0B0C10 -> #1E1B4B -> #312E81)
let bgColors: [CGColor] = [
    CGColor(srgbRed: 11/255.0, green: 12/255.0, blue: 16/255.0, alpha: 1.0),
    CGColor(srgbRed: 30/255.0, green: 27/255.0, blue: 75/255.0, alpha: 1.0),
    CGColor(srgbRed: 49/255.0, green: 46/255.0, blue: 129/255.0, alpha: 1.0)
]
let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]

if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: bgLocations) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 1024),
        end: CGPoint(x: 1024, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

// Helper to draw rounded rect
func addRoundedRect(in rect: CGRect, radius: CGFloat, to ctx: CGContext) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
}

// 2. Draw Subtle Radial Glow in Center
context.saveGState()
let glowColors: [CGColor] = [
    CGColor(srgbRed: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 0.25),
    CGColor(srgbRed: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 0.0)
]
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0.0, 1.0]) {
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 512, y: 512),
        startRadius: 50,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 450,
        options: []
    )
}
context.restoreGState()

// 3. Draw Back Card (Tilted Left -8°, semi-transparent Slate/Indigo)
context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: -8.0 * .pi / 180.0)
context.translateBy(x: -512, y: -512)

let backCardRect = CGRect(x: 272, y: 220, width: 480, height: 584)
addRoundedRect(in: backCardRect, radius: 48, to: context)
context.setFillColor(CGColor(srgbRed: 30/255.0, green: 41/255.0, blue: 59/255.0, alpha: 0.65))
context.fillPath()

// Back card border
addRoundedRect(in: backCardRect, radius: 48, to: context)
context.setStrokeColor(CGColor(srgbRed: 71/255.0, green: 85/255.0, blue: 105/255.0, alpha: 0.5))
context.setLineWidth(4)
context.strokePath()
context.restoreGState()

// 4. Draw Middle Card (Tilted Right +7°, semi-transparent Indigo)
context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: 7.0 * .pi / 180.0)
context.translateBy(x: -512, y: -512)

let midCardRect = CGRect(x: 272, y: 220, width: 480, height: 584)
addRoundedRect(in: midCardRect, radius: 48, to: context)
context.setFillColor(CGColor(srgbRed: 67/255.0, green: 56/255.0, blue: 202/255.0, alpha: 0.55))
context.fillPath()

addRoundedRect(in: midCardRect, radius: 48, to: context)
context.setStrokeColor(CGColor(srgbRed: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 0.6))
context.setLineWidth(4)
context.strokePath()
context.restoreGState()

// 5. Draw Front Card (Upright, Clean Shadow, Gradient Fill #16181F -> #1E1B4B)
context.saveGState()
let frontCardRect = CGRect(x: 272, y: 220, width: 480, height: 584)
context.setShadow(
    offset: CGSize(width: 0, height: -24),
    blur: 40,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
)

addRoundedRect(in: frontCardRect, radius: 48, to: context)
context.clip()

let frontColors: [CGColor] = [
    CGColor(srgbRed: 22/255.0, green: 24/255.0, blue: 31/255.0, alpha: 0.96),
    CGColor(srgbRed: 30/255.0, green: 27/255.0, blue: 75/255.0, alpha: 0.98)
]
if let frontGradient = CGGradient(colorsSpace: colorSpace, colors: frontColors as CFArray, locations: [0.0, 1.0]) {
    context.drawLinearGradient(
        frontGradient,
        start: CGPoint(x: 272, y: 804),
        end: CGPoint(x: 752, y: 220),
        options: []
    )
}
context.restoreGState()

// Front Card Glowing Border (#6366F1 / Accent Indigo)
context.saveGState()
addRoundedRect(in: frontCardRect, radius: 48, to: context)
context.setStrokeColor(CGColor(srgbRed: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 0.85))
context.setLineWidth(6)
context.strokePath()
context.restoreGState()

// 6. Photo Placeholders inside Front Card (Landscape mountain/sun silhouette)
context.saveGState()
addRoundedRect(in: frontCardRect, radius: 48, to: context)
context.clip()

// Sun / Moon circle
let sunCenter = CGPoint(x: 610, y: 590)
let sunRadius: CGFloat = 36
context.addArc(center: sunCenter, radius: sunRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
context.setFillColor(CGColor(srgbRed: 129/255.0, green: 140/255.0, blue: 248/255.0, alpha: 0.85))
context.fillPath()

// Back Mountain
context.beginPath()
context.move(to: CGPoint(x: 320, y: 350))
context.addLine(to: CGPoint(x: 460, y: 530))
context.addLine(to: CGPoint(x: 580, y: 380))
context.addLine(to: CGPoint(x: 320, y: 350))
context.closePath()
context.setFillColor(CGColor(srgbRed: 67/255.0, green: 56/255.0, blue: 202/255.0, alpha: 0.65))
context.fillPath()

// Front Mountain
context.beginPath()
context.move(to: CGPoint(x: 430, y: 350))
context.addLine(to: CGPoint(x: 560, y: 490))
context.addLine(to: CGPoint(x: 700, y: 350))
context.addLine(to: CGPoint(x: 430, y: 350))
context.closePath()
context.setFillColor(CGColor(srgbRed: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 0.85))
context.fillPath()
context.restoreGState()

// 7. Sparkle / Clean Icon (Top Right Corner of Front Card)
context.saveGState()
func drawSparkle(center: CGPoint, size: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    let half = size / 2
    let quarter = size / 6
    path.move(to: CGPoint(x: center.x, y: center.y - half))
    path.addQuadCurve(to: CGPoint(x: center.x + half, y: center.y), control: CGPoint(x: center.x + quarter, y: center.y - quarter))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + half), control: CGPoint(x: center.x + quarter, y: center.y + quarter))
    path.addQuadCurve(to: CGPoint(x: center.x - half, y: center.y), control: CGPoint(x: center.x - quarter, y: center.y + quarter))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - half), control: CGPoint(x: center.x - quarter, y: center.y - quarter))
    path.closeSubpath()
    
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

// Draw primary sparkle
drawSparkle(
    center: CGPoint(x: 690, y: 720),
    size: 110,
    color: CGColor(srgbRed: 244/255.0, green: 244/255.0, blue: 245/255.0, alpha: 0.95)
)

// Draw smaller secondary sparkle
drawSparkle(
    center: CGPoint(x: 740, y: 640),
    size: 55,
    color: CGColor(srgbRed: 165/255.0, green: 180/255.0, blue: 252/255.0, alpha: 0.85)
)
context.restoreGState()

// 8. Save PNG Image
guard let cgImage = context.makeImage() else {
    print("❌ Error: Failed to generate CGImage")
    exit(1)
}

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
bitmapRep.size = NSSize(width: width, height: height)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("❌ Error: Failed to encode PNG data")
    exit(1)
}

do {
    try pngData.write(to: outputImageURL)
    print("✅ AppIcon successfully saved to: \(outputImageURL.path)")
} catch {
    print("❌ Error: Failed to write PNG to \(outputImageURL.path): \(error)")
    exit(1)
}

// 9. Update Contents.json with filename
let contentsJSON = """
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

if let jsonData = contentsJSON.data(using: .utf8) {
    do {
        try jsonData.write(to: contentsJsonURL)
        print("✅ Updated Contents.json with AppIcon-1024.png")
    } catch {
        print("⚠️ Warning: Failed to update Contents.json: \(error)")
    }
}
