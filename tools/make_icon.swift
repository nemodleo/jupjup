// 앱 아이콘(디자인 캔버스 1번과 같은 그림) → Resources/AppIcon.icns
// 실행: swift tools/make_icon.swift
import AppKit

func draw(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    let k = CGFloat(px) / 1024
    // 디자인 좌표(200 상자, y 아래로) → 1024 아이콘 격자(824 타일, 여백 100)
    let s = 824.0 / 180.0 * k, o = 100 * k - 10 * s
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: o, y: o); ctx.scaleBy(x: s, y: s)
    let mook = CGColor(srgbRed: 0x1F/255, green: 0x1D/255, blue: 0x1A/255, alpha: 1)
    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: 180, height: 180), cornerWidth: 40, cornerHeight: 40, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0xF6/255, green: 0xF2/255, blue: 0xEA/255, alpha: 1)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let big = px >= 64
    ctx.setStrokeColor(mook); ctx.setLineWidth(big ? 7 : 10); ctx.setLineCap(.square)
    for pts in [[(50, 72), (50, 52), (70, 52)], [(130, 52), (150, 52), (150, 72)], [(150, 128), (150, 148), (130, 148)], [(70, 148), (50, 148), (50, 128)]] {
        ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); ctx.addLine(to: CGPoint(x: pts[1].0, y: pts[1].1)); ctx.addLine(to: CGPoint(x: pts[2].0, y: pts[2].1))
    }
    ctx.strokePath()
    ctx.setFillColor(mook)
    ctx.fill(CGRect(x: 72, y: big ? 84 : 82, width: 58, height: big ? 9 : 12))
    ctx.fill(CGRect(x: 72, y: big ? 121 : 120, width: 40, height: big ? 9 : 12))
    if big { ctx.setFillColor(mook.copy(alpha: 0.12)!); ctx.fill(CGRect(x: 72, y: 103, width: 58, height: 9)) }
    ctx.saveGState()
    ctx.translateBy(x: 117, y: 101); ctx.rotate(by: -6 * .pi / 180)
    ctx.setFillColor(CGColor(srgbRed: 0xC4/255, green: 0x55/255, blue: 0x3A/255, alpha: 1))
    ctx.fill(CGRect(x: -31, y: big ? -5 : -6.5, width: 62, height: big ? 10 : 13))
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! draw(px: pt * scale).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil 실패")
