// 生成 DeepSeek Harness Shell 应用图标（icns 所需 iconset）。
// 用法：swift Scripts/make-icon.swift <输出 iconset 目录>
//
// 注意：所有绘制必须发生在最终要 makeImage() 的那个 CGContext 里，
// 不要在辅助函数中另建 CGContext（否则画进被丢弃的上下文，图标会是空白）。
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawIcon(in context: CGContext) {
    // 背景：DeepSeek 蓝渐变圆角方块
    let backgroundRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let backgroundPath = CGPath(
        roundedRect: backgroundRect,
        cornerWidth: 224,
        cornerHeight: 224,
        transform: nil
    )
    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let topColor = NSColor(calibratedRed: 0.32, green: 0.49, blue: 1.00, alpha: 1).cgColor
    let bottomColor = NSColor(calibratedRed: 0.045, green: 0.085, blue: 0.26, alpha: 1).cgColor
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [topColor, bottomColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: 1024),
        end: CGPoint(x: 512, y: 0),
        options: []
    )

    // 终端窗口卡片：半透明白 + 左上三色灯
    let card = NSBezierPath(
        roundedRect: NSRect(x: 168, y: 232, width: 688, height: 560),
        xRadius: 104,
        yRadius: 104
    )
    NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
    card.fill()

    let lights: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (1.00, 0.36, 0.36, 272),
        (1.00, 0.78, 0.32, 322),
        (0.36, 0.80, 0.44, 372)
    ]
    for (r, g, b, x) in lights {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 720, width: 34, height: 34)).fill()
    }

    // 主视觉：白色 `>_`（等宽字体，重心略下移）
    let font = NSFont.monospacedSystemFont(ofSize: 290, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let text = NSAttributedString(string: ">_", attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(
        x: (1024 - textSize.width) / 2,
        y: 370 - textSize.height / 2
    ))
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

    // 让 AppKit 路径/文字绘制与 CoreGraphics 操作共用同一个上下文。
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

// 校验：读取最大尺寸 PNG 并抽样，防止再次生成透明/纯色空白图标。
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
let checkPoints = [(512, 100), (512, 512), (512, 900), (100, 512), (900, 512)]
let samples = try samplePixels(at: checkURL, points: checkPoints)
let variance = Set(samples).count
if variance <= 2 {
    fputs("error: generated icon looks blank (pixel variance \(variance))\n", stderr)
    exit(1)
}
print("iconset written to \(outputDirectory.path) (pixel check passed, variance \(variance))")
