import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make_dmg_background.swift <output-png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1064
let height = 768
let size = CGSize(width: width, height: height)

let image = NSImage(size: size)
image.lockFocus()

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func drawText(_ text: String, rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)
let background = NSBezierPath(rect: CGRect(origin: .zero, size: size))
color(0xf4f8fe).setFill()
background.fill()

let context = NSGraphicsContext.current!.cgContext
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        color(0xffffff, alpha: 1).cgColor,
        color(0xdcecff, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: width, y: 0),
    options: []
)

color(0xffffff, alpha: 0.56).setStroke()
for offset in stride(from: -180, through: 1240, by: 360) {
    let path = NSBezierPath()
    path.lineWidth = 10
    path.move(to: CGPoint(x: CGFloat(offset), y: 95))
    path.curve(
        to: CGPoint(x: CGFloat(offset + 420), y: 130),
        controlPoint1: CGPoint(x: CGFloat(offset + 130), y: 45),
        controlPoint2: CGPoint(x: CGFloat(offset + 260), y: 175)
    )
    path.stroke()
}

let panelRect = CGRect(x: 54, y: 72, width: 956, height: 636)
NSShadow().apply {
    $0.shadowColor = color(0x8aa6c8, alpha: 0.22)
    $0.shadowOffset = CGSize(width: 0, height: -8)
    $0.shadowBlurRadius = 22
}
let panel = NSBezierPath(roundedRect: panelRect, xRadius: 32, yRadius: 32)
color(0xffffff, alpha: 0.93).setFill()
panel.fill()
NSShadow().set()
color(0xdfe8f2, alpha: 0.9).setStroke()
panel.lineWidth = 1
panel.stroke()

drawText(
    "将 Codex TaskGuard 拖入 Applications 完成安装",
    rect: CGRect(x: 150, y: 602, width: 764, height: 42),
    font: .systemFont(ofSize: 30, weight: .bold),
    color: color(0x243040)
)
drawText(
    "Drag Codex TaskGuard into Applications to install",
    rect: CGRect(x: 220, y: 568, width: 624, height: 28),
    font: .systemFont(ofSize: 21, weight: .medium),
    color: color(0x7a8798)
)

func drawTarget(center: CGPoint) {
    for (index, radius) in [108, 92, 76].enumerated() {
        let rect = CGRect(
            x: center.x - CGFloat(radius),
            y: center.y - CGFloat(radius),
            width: CGFloat(radius * 2),
            height: CGFloat(radius * 2)
        )
        let path = NSBezierPath(ovalIn: rect)
        color(0xcbd9ea, alpha: index == 0 ? 0.55 : 0.34).setStroke()
        path.lineWidth = index == 0 ? 1.6 : 1.2
        path.stroke()
    }
}

let appCenter = CGPoint(x: 226, y: 336)
let applicationsCenter = CGPoint(x: 838, y: 336)
drawTarget(center: appCenter)
drawTarget(center: applicationsCenter)

let arrow = NSBezierPath()
arrow.lineWidth = 2.5
arrow.move(to: CGPoint(x: 386, y: 336))
arrow.line(to: CGPoint(x: 678, y: 336))
arrow.move(to: CGPoint(x: 655, y: 360))
arrow.line(to: CGPoint(x: 680, y: 336))
arrow.line(to: CGPoint(x: 655, y: 312))
color(0x9db0c8, alpha: 0.95).setStroke()
arrow.stroke()

let docBox = NSBezierPath(roundedRect: CGRect(x: 454, y: 132, width: 156, height: 142), xRadius: 18, yRadius: 18)
color(0xc8d6e8, alpha: 0.58).setStroke()
docBox.lineWidth = 1.6
docBox.setLineDash([7, 5], count: 2, phase: 0)
docBox.stroke()
docBox.setLineDash(nil, count: 0, phase: 0)

drawText(
    "安装说明",
    rect: CGRect(x: 454, y: 98, width: 156, height: 24),
    font: .systemFont(ofSize: 18, weight: .semibold),
    color: color(0x303846)
)

drawText(
    "首次打开被拦截时，请查看安装说明",
    rect: CGRect(x: 250, y: 42, width: 564, height: 28),
    font: .systemFont(ofSize: 18, weight: .semibold),
    color: color(0x95a1b2)
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render background\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)

private extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}
