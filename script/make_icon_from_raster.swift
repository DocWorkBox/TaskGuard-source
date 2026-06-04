import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("usage: make_icon_from_raster.swift <source-png> <resources-dir> <icon-name>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let resourcesURL = URL(fileURLWithPath: CommandLine.arguments[2])
let iconName = CommandLine.arguments[3]
let fileManager = FileManager.default
try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

guard let source = NSImage(contentsOf: sourceURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fputs("failed to load source image: \(sourceURL.path)\n", stderr)
    exit(1)
}

let sourceWidth = sourceCG.width
let sourceHeight = sourceCG.height

// Candidate 1 from the 4x2 imagegen board. Coordinates are in top-left image space.
let crop = CGRect(
    x: CGFloat(sourceWidth) * 0.018,
    y: CGFloat(sourceHeight) * 0.055,
    width: CGFloat(sourceWidth) * 0.238,
    height: CGFloat(sourceHeight) * 0.370
).integral

guard let cropped = sourceCG.cropping(to: crop) else {
    fputs("failed to crop source image\n", stderr)
    exit(1)
}

func bitmapContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("failed to create bitmap context")
    }
    return context
}

func transparentBackgroundImage(from image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let context = bitmapContext(width: width, height: height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let data = context.data else { fatalError("missing bitmap data") }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

    func isBackgroundCandidate(x: Int, y: Int) -> Bool {
        let index = (y * width + x) * 4
        let r = Double(pixels[index])
        let g = Double(pixels[index + 1])
        let b = Double(pixels[index + 2])
        let maxChannel = max(r, max(g, b))
        let minChannel = min(r, min(g, b))
        let saturation = maxChannel - minChannel
        return maxChannel > 158 && saturation < 62
    }

    var visited = Array(repeating: false, count: width * height)
    var queue: [(Int, Int)] = []

    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let position = y * width + x
        guard !visited[position], isBackgroundCandidate(x: x, y: y) else { return }
        visited[position] = true
        queue.append((x, y))
    }

    for x in 0..<width {
        enqueue(x, 0)
        enqueue(x, height - 1)
    }
    for y in 0..<height {
        enqueue(0, y)
        enqueue(width - 1, y)
    }

    var queueIndex = 0
    while queueIndex < queue.count {
        let (x, y) = queue[queueIndex]
        queueIndex += 1
        enqueue(x + 1, y)
        enqueue(x - 1, y)
        enqueue(x, y + 1)
        enqueue(x, y - 1)
    }

    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let isConnectedBackground = visited[y * width + x]
            let alpha: UInt8
            if isConnectedBackground {
                alpha = 0
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
            } else {
                alpha = 255
            }

            pixels[index + 3] = alpha

            if alpha > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX < maxX, minY < maxY, let processed = context.makeImage() else {
        return image
    }

    let contentWidth = maxX - minX + 1
    let contentHeight = maxY - minY + 1
    let padding = 14
    let contentRect = CGRect(
        x: max(0, minX - padding),
        y: max(0, minY - padding),
        width: min(width - max(0, minX - padding), contentWidth + padding * 2),
        height: min(height - max(0, minY - padding), contentHeight + padding * 2)
    ).integral

    return processed.cropping(to: contentRect) ?? processed
}

let foreground = transparentBackgroundImage(from: cropped)

func renderIcon(size: Int) -> CGImage {
    let context = bitmapContext(width: size, height: size)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high

    let inset = CGFloat(size) * 0.055
    let available = CGFloat(size) - inset * 2
    let scale = min(available / CGFloat(foreground.width), available / CGFloat(foreground.height))
    let drawWidth = CGFloat(foreground.width) * scale
    let drawHeight = CGFloat(foreground.height) * scale
    let drawRect = CGRect(
        x: (CGFloat(size) - drawWidth) / 2,
        y: (CGFloat(size) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )

    context.draw(foreground, in: drawRect)
    removeOuterShadow(in: context, size: size)
    guard let image = context.makeImage() else {
        fatalError("failed to render icon")
    }
    return image
}

func removeOuterShadow(in context: CGContext, size: Int) {
    guard let data = context.data else { return }
    let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
    let inset = Double(size) * 0.105
    let radius = Double(size) * 0.145
    let minX = inset
    let minY = inset
    let maxX = Double(size) - inset
    let maxY = Double(size) - inset

    func insideRoundedRect(_ x: Double, _ y: Double) -> Bool {
        if x < minX || x > maxX || y < minY || y > maxY {
            return false
        }

        let cornerX = x < minX + radius ? minX + radius : (x > maxX - radius ? maxX - radius : x)
        let cornerY = y < minY + radius ? minY + radius : (y > maxY - radius ? maxY - radius : y)
        let dx = x - cornerX
        let dy = y - cornerY
        return dx * dx + dy * dy <= radius * radius
    }

    for y in 0..<size {
        for x in 0..<size {
            guard !insideRoundedRect(Double(x), Double(y)) else { continue }
            let index = (y * size + x) * 4
            pixels[index] = 0
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 0
        }
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "CodexTaskGuardIcon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CodexTaskGuardIcon", code: 2)
    }
}

let iconsetURL = resourcesURL.appendingPathComponent("\(iconName).iconset")
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

for (size, scale, filename) in sizes {
    try writePNG(renderIcon(size: size * scale), to: iconsetURL.appendingPathComponent(filename))
}

try writePNG(renderIcon(size: 1024), to: resourcesURL.appendingPathComponent("\(iconName)-preview.png"))
