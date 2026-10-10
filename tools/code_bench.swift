// QR 스타일 채점: 진짜 QR을 15가지 모양(둥근·점·로고·색·반전·작게·기울임·틀·흐림)으로 그려 Recognizer.codes가 읽는지 본다.
// main.swift로 복사해서 swiftc -O Sources/Recognizer.swift main.swift -o t && ./t <그림 저장 폴더> [기준 개수]
// 05(눈까지 점)·10(40px, 비레티나)은 폰 카메라도 못 읽는 수준이라 기준은 13.
import AppKit
import CoreImage
import Vision

// CIQRCodeGenerator를 1모듈=1px로 돌려 행렬을 뽑고, 여러 스타일로 다시 그려 줍줍(Recognizer.codes)이 읽는지 본다
let msg = "https://github.com/nemodleo/jupjup"
func matrix(level: String) -> [[Bool]] {
    let f = CIFilter(name: "CIQRCodeGenerator")!; f.setValue(msg.data(using: .utf8), forKey: "inputMessage"); f.setValue(level, forKey: "inputCorrectionLevel")
    let ci = f.outputImage!; let cg = CIContext().createCGImage(ci, from: ci.extent)!
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    // CI 출력은 사방 2모듈 여백(quiet zone). 위가 0행이 되게 뒤집는다
    return (0..<h).map { y in (0..<w).map { x in buf[(h - 1 - y) * w + x] < 128 } }
}
let mH = matrix(level: "H")
let n = mH.count // 여백 포함 모듈 수

struct Style { let name: String; let draw: (CGContext, CGFloat) -> Void; var size: CGFloat = 320; var ec: [[Bool]] = mH; var pad: CGFloat = 24; var bg = NSColor.white }

func inFinder(_ r: Int, _ c: Int) -> Bool { // 세 모서리 위치 패턴(7×7)인가
    let q = 2, k = n - 2 // 여백 2
    return (r >= q && r < q + 7 && c >= q && c < q + 7) || (r >= q && r < q + 7 && c >= k - 7 && c < k) || (r >= k - 7 && r < k && c >= q && c < q + 7)
}
func modules(_ ctx: CGContext, _ m: [[Bool]], _ cell: CGFloat, _ body: (CGRect, Bool) -> Void) {
    for r in 0..<n { for c in 0..<n where m[r][c] { body(CGRect(x: CGFloat(c) * cell, y: CGFloat(n - 1 - r) * cell, width: cell, height: cell), inFinder(r, c)) } }
}
let ink = NSColor.black.cgColor
func square(_ m: [[Bool]], color: CGColor = ink) -> (CGContext, CGFloat) -> Void { { ctx, cell in ctx.setFillColor(color); modules(ctx, m, cell) { r, _ in ctx.fill(r) } } }
func dots(_ m: [[Bool]], color: CGColor = ink, finderSquare: Bool = true, shrink: CGFloat = 0.85) -> (CGContext, CGFloat) -> Void { { ctx, cell in
    ctx.setFillColor(color)
    modules(ctx, m, cell) { r, fin in if fin && finderSquare { ctx.fill(r) } else { ctx.fillEllipse(in: r.insetBy(dx: cell * (1 - shrink) / 2, dy: cell * (1 - shrink) / 2)) } } } }
func rounded(_ m: [[Bool]]) -> (CGContext, CGFloat) -> Void { { ctx, cell in
    ctx.setFillColor(ink); modules(ctx, m, cell) { r, _ in ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: cell * 0.35, cornerHeight: cell * 0.35, transform: nil)); ctx.fillPath() } } }
func logo(_ ctx: CGContext, _ side: CGFloat) { // 가운데 흰 원 + 색 글자 G
    let d = side * 0.26; let r = CGRect(x: (side - d) / 2, y: (side - d) / 2, width: d, height: d)
    ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: r)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let s = NSAttributedString(string: "G", attributes: [.font: NSFont.boldSystemFont(ofSize: d * 0.6), .foregroundColor: NSColor.systemBlue])
    let sz = s.size(); s.draw(at: NSPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
}

var styles: [Style] = [
    Style(name: "01 기본 네모", draw: square(mH)),
    Style(name: "02 둥근 모듈", draw: rounded(mH)),
    Style(name: "03 점 모듈(눈은 네모)", draw: dots(mH)),
    Style(name: "04 점 모듈 + 가운데 로고(EC H)", draw: { ctx, cell in dots(mH)(ctx, cell); logo(ctx, cell * CGFloat(n)) }, ec: mH),
    Style(name: "05 눈까지 점(작은 점 0.7)", draw: dots(mH, finderSquare: false, shrink: 0.7)),
    Style(name: "06 파란 모듈·연노랑 배경", draw: square(mH, color: NSColor.systemBlue.cgColor), bg: NSColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)),
    Style(name: "07 반전(흰 모듈·검은 배경)", draw: square(mH, color: NSColor.white.cgColor), bg: .black),
    Style(name: "08 낮은 대비(회색 60%)", draw: square(mH, color: NSColor(white: 0.6, alpha: 1).cgColor)),
    Style(name: "09 작게 60px", draw: square(mH), size: 60, pad: 8),
    Style(name: "10 아주 작게 40px", draw: square(mH), size: 40, pad: 6),
    Style(name: "11 여백 0", draw: square(mH), pad: 0),
    Style(name: "12 기울임 12°", draw: { ctx, cell in let s = cell * CGFloat(n); ctx.translateBy(x: s / 2, y: s / 2); ctx.rotate(by: 12 * .pi / 180); ctx.translateBy(x: -s / 2, y: -s / 2); square(mH)(ctx, cell) }, pad: 60),
    Style(name: "13 SCAN ME 틀(모서리 괄호+라벨)", draw: { ctx, cell in
        let s = cell * CGFloat(n); square(mH)(ctx, cell)
        ctx.setStrokeColor(ink); ctx.setLineWidth(6)
        for (x, y, dx, dy) in [(0, 0, 1, 1), (s, 0, -1, 1), (0, s, 1, -1), (s, s, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: x, y: y + dy * 40)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + dx * 40, y: y)); ctx.strokePath()
        }
        ctx.setFillColor(ink); ctx.fill(CGRect(x: s * 0.2, y: -70, width: s * 0.6, height: 50))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: "SCAN ME", attributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: s * 0.2 + 28, y: -62))
        NSGraphicsContext.restoreGraphicsState() }, pad: 80),
    Style(name: "14 흐림(blur 2px)", draw: square(mH)),
    Style(name: "15 글자 사이에 작은 QR 90px", draw: square(mH), size: 90, pad: 10),
]

func render(_ st: Style) -> CGImage {
    let cell = st.size / CGFloat(n), side = st.size
    let w = side + st.pad * 2, h = side + st.pad * 2
    let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(st.bg.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.saveGState(); ctx.translateBy(x: st.pad, y: st.pad); st.draw(ctx, cell); ctx.restoreGState()
    var img = ctx.makeImage()!
    if st.name.hasPrefix("14") {
        let ci = CIImage(cgImage: img).applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2]).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        img = CIContext().createCGImage(ci, from: ci.extent)!
    }
    if st.name.hasPrefix("15") { // 본문 글 사이에 끼워 넣기
        let W = 700.0, H = 220.0
        let c2 = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c2.setFillColor(NSColor.white.cgColor); c2.fill(CGRect(x: 0, y: 0, width: W, height: H))
        c2.draw(img, in: CGRect(x: 20, y: 50, width: CGFloat(img.width), height: CGFloat(img.height)))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c2, flipped: false)
        NSAttributedString(string: "앱 다운로드는 QR을 찍으세요.\n문의: help@example.com", attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 150, y: 90))
        NSGraphicsContext.restoreGraphicsState()
        img = c2.makeImage()!
    }
    return img
}

let outDir = CommandLine.arguments[1]
var ok = 0
for st in styles {
    let img = render(st)
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(outDir)/\(st.name.prefix(2)).png"))
    let codes = Recognizer.codes(img)
    let hit = codes.contains { $0.payload == msg }
    if hit { ok += 1 }
    print(hit ? "✓" : "✗", st.name, "(\(img.width)×\(img.height))", hit ? "" : codes.map(\.payload).joined())
}
let need = Int(CommandLine.arguments.dropFirst(2).first ?? "13") ?? 13
print("\(ok)/\(styles.count) · 기준 \(need)")
exit(ok < need ? 1 : 0)
