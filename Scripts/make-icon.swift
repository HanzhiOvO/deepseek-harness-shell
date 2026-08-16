// 生成 DeepSeek Harness Shell 应用图标（icns 所需 iconset）。
// 用法：swift Scripts/make-icon.swift <输出 iconset 目录>
//
// 视觉：官方 DeepSeek Harness 图标（白色版）叠加 DeepSeek 蓝渐变底色。
// 注意：所有绘制必须发生在最终要 makeImage() 的那个 CGContext 里。
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawIcon(in context: CGContext) {
    let backgroundRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let backgroundPath = CGPath(
        roundedRect: backgroundRect,
        cornerWidth: 185,
        cornerHeight: 185,
        transform: nil
    )

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()

    // 1. DeepSeek 蓝背景
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let topColor = NSColor(calibratedRed: 0.24, green: 0.38, blue: 1.00, alpha: 1).cgColor
    let bottomColor = NSColor(calibratedRed: 0.025, green: 0.065, blue: 0.24, alpha: 1).cgColor
    let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [topColor, bottomColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 300, y: 1050),
        end: CGPoint(x: 750, y: -40),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 2. 官方 DeepSeek Harness 图标（白色版）+ 底色
    let scriptDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let svgURL = scriptDirectory
        .appendingPathComponent("../Resources/HarnessIconWhite.svg", isDirectory: false)
        .standardizedFileURL
    if let harnessIcon = NSImage(contentsOf: svgURL) {
        harnessIcon.draw(
            in: NSRect(x: 152, y: 152, width: 720, height: 720),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    } else {
        fputs("warning: official harness icon not found at \(svgURL.path)\n", stderr)
    }

    context.restoreGState()
}

func render(size: CGFloat, to url: URL) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "icon", code: 1) }

    let scale = size / 1024.0
    context.scaleBy(x: scale, y: scale)

    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphics
    NSGraphicsContext.saveGraphicsState()
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else { throw NSError(domain: "icon", code: 2) }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 3) }
}

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in sizes {
    try render(size: entry.size, to: outputDirectory.appendingPathComponent(entry.name))
}

// 校验：抽样确保不是透明/纯色空白图标。
func samplePixels(at url: URL, points: [(Int, Int)]) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "icon", code: 4)
    }
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "icon", code: 5) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var samples: [UInt8] = []
    for (x, y) in points {
        let offset = (y * width + x) * 4
        samples.append(pixels[offset])
        samples.append(pixels[offset + 1])
        samples.append(pixels[offset + 2])
        samples.append(pixels[offset + 3])
    }
    return samples
}

let checkURL = outputDirectory.appendingPathComponent("icon_512x512@2x.png")
let checkPoints = [
    (512, 100), (512, 400), (512, 900), (100, 512), (900, 512),
    (120, 120), (120, 904), (904, 120), (904, 904)
]
let samples = try samplePixels(at: checkURL, points: checkPoints)
let variance = Set(samples).count
if variance <= 2 {
    fputs("error: generated icon looks blank (pixel variance \(variance))\n", stderr)
    exit(1)
}
print("iconset written to \(outputDirectory.path) (pixel check passed, variance \(variance))")
