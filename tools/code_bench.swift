// QR·바코드 채점: 진짜 QR을 여러 모양·상태로 그려 Recognizer.codes가 읽는지 본다.
// 기준은 "아이폰 카메라 앱이 읽는 것": 모양 꾸밈(둥근·점·하트·마름모·선·물방울·원/팔각 눈·로고), 색·반전·저대비,
// 작게·흐림·JPEG·잡음·원근·회전, 큰 화면 속 작은 코드, 한 장에 둘. 가짜(QR 모양만 있는 그림)는 아무것도 안 나와야 함.
// main.swift로 복사해서 swiftc -O Sources/Recognizer.swift main.swift -o t && ./t <그림 폴더> [기준 개수] [-basic]
// -basic: 예전 방식(한 번만 보기)으로 채점해 비교.
import AppKit
import CoreImage

let msg = "https://github.com/nemodleo/jupjup"
let basic = CommandLine.arguments.contains("-basic")

// MARK: QR 행렬 (CIQRCodeGenerator를 1모듈=1픽셀로)
func matrix(_ text: String, level: String) -> [[Bool]] {
    let f = CIFilter(name: "CIQRCodeGenerator")!
    f.setValue(text.data(using: .utf8), forKey: "inputMessage"); f.setValue(level, forKey: "inputCorrectionLevel")
    let ci = f.outputImage!; let cg = CIContext().createCGImage(ci, from: ci.extent)!
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let full = (0..<h).map { y in (0..<w).map { x in buf[(h - 1 - y) * w + x] < 128 } }
    // 여백을 걷어내고 모듈만
    let rows = full.indices.filter { full[$0].contains(true) }, cols = full[0].indices.filter { c in full.contains { $0[c] } }
    return rows.map { r in cols.map { full[r][$0] } }
}

enum Shape { case square, rounded, dot(CGFloat), diamond, heart, vline, liquid }
enum Eye { case square, rounded, circle, octagon, asModules }

struct Style {
    var shape: Shape = .square
    var eye: Eye = .square
    var ink: CGColor = .black
    var paper: CGColor = .white
    var gradient: (CGColor, CGColor)?
    var logo: CGFloat = 0          // 가운데 로고가 덮는 한 변 비율
    var level = "M"
}

func isEye(_ r: Int, _ c: Int, _ n: Int) -> Bool { (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7) }

/// 행렬을 그 모양대로 그린다. side = QR 한 변(px), 여백 quiet(모듈 수)
func drawQR(_ st: Style, side: CGFloat, quiet: CGFloat = 4) -> CGImage {
    let m = matrix(msg, level: st.level), n = m.count
    let cell = side / CGFloat(n), total = side + 2 * quiet * cell
    let W = Int(total.rounded())
    let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(st.paper); ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))
    // 모듈은 먼저 마스크(검정)로 그린 뒤 색(또는 그라데이션)을 입힌다
    let mask = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    mask.setFillColor(gray: 0, alpha: 1); mask.fill(CGRect(x: 0, y: 0, width: W, height: W))
    mask.setFillColor(gray: 1, alpha: 1); mask.setStrokeColor(gray: 1, alpha: 1)
    let o = quiet * cell
    func rect(_ r: Int, _ c: Int) -> CGRect { CGRect(x: o + CGFloat(c) * cell, y: total - o - CGFloat(r + 1) * cell, width: cell, height: cell) }
    for r in 0..<n { for c in 0..<n where m[r][c] {
        if isEye(r, c, n) && !{ if case .asModules = st.eye { return true }; return false }() { continue }
        let b = rect(r, c)
        switch st.shape {
        case .square: mask.fill(b)
        case .rounded: mask.addPath(CGPath(roundedRect: b.insetBy(dx: cell * 0.04, dy: cell * 0.04), cornerWidth: cell * 0.35, cornerHeight: cell * 0.35, transform: nil)); mask.fillPath()
        case .dot(let k): mask.fillEllipse(in: b.insetBy(dx: cell * (1 - k) / 2, dy: cell * (1 - k) / 2))
        case .diamond:
            mask.move(to: CGPoint(x: b.midX, y: b.maxY)); mask.addLine(to: CGPoint(x: b.maxX, y: b.midY))
            mask.addLine(to: CGPoint(x: b.midX, y: b.minY)); mask.addLine(to: CGPoint(x: b.minX, y: b.midY)); mask.closePath(); mask.fillPath()
        case .heart:
            let s = cell * 0.9, x = b.midX, y = b.midY
            mask.fillEllipse(in: CGRect(x: x - s / 2, y: y - s * 0.05, width: s / 2, height: s / 2))
            mask.fillEllipse(in: CGRect(x: x, y: y - s * 0.05, width: s / 2, height: s / 2))
            mask.move(to: CGPoint(x: x - s / 2 + s * 0.02, y: y + s * 0.12)); mask.addLine(to: CGPoint(x: x + s / 2 - s * 0.02, y: y + s * 0.12))
            mask.addLine(to: CGPoint(x: x, y: y - s / 2)); mask.closePath(); mask.fillPath()
        case .vline: mask.fill(b.insetBy(dx: cell * 0.3, dy: 0))
        case .liquid:
            mask.fillEllipse(in: b)
            if c + 1 < n, m[r][c + 1], !isEye(r, c + 1, n) { mask.fill(CGRect(x: b.midX, y: b.minY, width: cell, height: cell)) }
            if r + 1 < n, m[r + 1][c], !isEye(r + 1, c, n) { mask.fill(CGRect(x: b.minX, y: b.minY - cell / 2, width: cell, height: cell)) }
        }
    } }
    // 눈(위치 패턴) — 7×7 바깥 고리 + 3×3 가운데
    for (er, ec) in [(0, 0), (0, n - 7), (n - 7, 0)] {
        if case .asModules = st.eye { break }
        let outer = rect(er, ec).union(rect(er + 6, ec + 6)), inner = rect(er + 2, ec + 2).union(rect(er + 4, ec + 4))
        let ring = outer.insetBy(dx: cell / 2, dy: cell / 2)
        mask.setLineWidth(cell)
        switch st.eye {
        case .square: mask.stroke(ring); mask.fill(inner)
        case .rounded:
            mask.addPath(CGPath(roundedRect: ring, cornerWidth: cell * 1.6, cornerHeight: cell * 1.6, transform: nil)); mask.strokePath()
            mask.addPath(CGPath(roundedRect: inner, cornerWidth: cell * 0.8, cornerHeight: cell * 0.8, transform: nil)); mask.fillPath()
        case .circle: mask.strokeEllipse(in: ring); mask.fillEllipse(in: inner)
        case .octagon:
            func oct(_ r: CGRect) -> CGPath { let k = r.width * 0.29; let p = CGMutablePath()
                p.addLines(between: [CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY), CGPoint(x: r.maxX, y: r.minY + k), CGPoint(x: r.maxX, y: r.maxY - k),
                                     CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY), CGPoint(x: r.minX, y: r.maxY - k), CGPoint(x: r.minX, y: r.minY + k)]); p.closeSubpath(); return p }
            mask.addPath(oct(ring)); mask.strokePath(); mask.addPath(oct(inner)); mask.fillPath()
        case .asModules: break
        }
    }
    ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: W), mask: mask.makeImage()!)
    if let (a, b) = st.gradient {
        ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [a, b] as CFArray, locations: nil)!,
                               start: .zero, end: CGPoint(x: W, y: W), options: [])
    } else { ctx.setFillColor(st.ink); ctx.fill(CGRect(x: 0, y: 0, width: W, height: W)) }
    ctx.restoreGState()
    if st.logo > 0 { // 흰 둥근 판 위에 색 원(로고 자리)
        let d = side * st.logo, rr = CGRect(x: (total - d) / 2, y: (total - d) / 2, width: d, height: d)
        ctx.setFillColor(st.paper); ctx.addPath(CGPath(roundedRect: rr.insetBy(dx: -cell * 0.6, dy: -cell * 0.6), cornerWidth: d * 0.2, cornerHeight: d * 0.2, transform: nil)); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0.85, green: 0.25, blue: 0.55, alpha: 1)); ctx.addPath(CGPath(roundedRect: rr, cornerWidth: d * 0.22, cornerHeight: d * 0.22, transform: nil)); ctx.fillPath()
        ctx.setStrokeColor(.white); ctx.setLineWidth(d * 0.08); ctx.strokeEllipse(in: rr.insetBy(dx: d * 0.28, dy: d * 0.28))
    }
    return ctx.makeImage()!
}

// MARK: 상태(찍힌 모습)
let ciCtx = CIContext()
func cg(_ i: CIImage, _ ext: CGRect) -> CGImage { ciCtx.createCGImage(i, from: ext)! }
func blur(_ img: CGImage, _ r: CGFloat) -> CGImage { let c = CIImage(cgImage: img); return cg(c.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": r]), c.extent) }
func jpeg(_ img: CGImage, _ q: CGFloat) -> CGImage {
    let d = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: q])!
    return NSBitmapImageRep(data: d)!.cgImage!
}
func noise(_ img: CGImage, _ amt: CGFloat) -> CGImage {
    let c = CIImage(cgImage: img)
    let n = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: c.extent)
        .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: amt, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: amt, z: 0, w: 0),
                                                      "inputBVector": CIVector(x: 0, y: 0, z: amt, w: 0), "inputBiasVector": CIVector(x: -amt / 2, y: -amt / 2, z: -amt / 2, w: 0)])
    return cg(n.applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": c]), c.extent)
}
func resample(_ img: CGImage, _ s: CGFloat) -> CGImage { // 작게 찍혔다가(화면 속 작은 QR) 다시 원래 크기로 보이는 것
    let small = CGContext(data: nil, width: max(1, Int(CGFloat(img.width) * s)), height: max(1, Int(CGFloat(img.height) * s)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    small.interpolationQuality = .high; small.draw(img, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
    return small.makeImage()!
}
func rotate(_ img: CGImage, _ deg: CGFloat) -> CGImage {
    let c = CIImage(cgImage: img); let r = c.transformed(by: CGAffineTransform(rotationAngle: deg * .pi / 180))
    let bg = CIImage(color: .white).cropped(to: r.extent.insetBy(dx: -20, dy: -20))
    let out = r.composited(over: bg); return cg(out, out.extent)
}
func perspective(_ img: CGImage, _ k: CGFloat) -> CGImage {
    let c = CIImage(cgImage: img); let w = c.extent.width, h = c.extent.height
    let p = c.applyingFilter("CIPerspectiveTransform", parameters: ["inputTopLeft": CIVector(x: w * k, y: h * (1 - k * 0.3)), "inputTopRight": CIVector(x: w * (1 - k * 0.2), y: h),
                                                                 "inputBottomLeft": CIVector(x: 0, y: 0), "inputBottomRight": CIVector(x: w, y: h * k * 0.4)])
    let bg = CIImage(color: .white).cropped(to: p.extent.insetBy(dx: -20, dy: -20))
    let out = p.composited(over: bg); return cg(out, out.extent)
}
/// 큰 화면 한 장(1512×982pt @2x의 절반 크기) 안 어딘가에 작게
func onScreen(_ qr: CGImage, at p: CGPoint, size: CGFloat, text: Bool = true) -> CGImage {
    let W = 1600, H = 1000
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    if text {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for i in 0..<28 { ("행사 안내 · 입장은 QR로 확인합니다. Please scan the code at the entrance. 문의 02-1234-5678 " as NSString)
            .draw(at: NSPoint(x: 40, y: 40 + i * 33), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor(white: 0.25, alpha: 1)]) }
        NSGraphicsContext.restoreGraphicsState()
    }
    ctx.setFillColor(.white); ctx.fill(CGRect(x: p.x - 6, y: p.y - 6, width: size + 12, height: size + 12))
    ctx.interpolationQuality = .high; ctx.draw(qr, in: CGRect(x: p.x, y: p.y, width: size, height: size))
    return ctx.makeImage()!
}
func side2(_ a: CGImage, _ b: CGImage) -> CGImage {
    let W = a.width + b.width + 60, H = max(a.height, b.height) + 40
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.draw(a, in: CGRect(x: 20, y: 20, width: a.width, height: a.height)); ctx.draw(b, in: CGRect(x: a.width + 40, y: 20, width: b.width, height: b.height))
    return ctx.makeImage()!
}
/// 가짜: QR처럼 보이지만 규격이 아닌 무늬(눈 셋 + 무작위 칸). 아무것도 나오면 안 됨
func fake(seed: Int) -> CGImage {
    var g = UInt64(seed * 2654435761 + 1)
    func rnd() -> Bool { g = g &* 6364136223846793005 &+ 1442695040888963407; return (g >> 33) & 1 == 1 }
    let n = 23, cell: CGFloat = 12, W = Int(CGFloat(n + 8) * cell)
    let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: W, height: W)); ctx.setFillColor(.black)
    for r in 0..<n { for c in 0..<n where isEye(r, c, n) ? false : rnd() { ctx.fill(CGRect(x: CGFloat(c + 4) * cell, y: CGFloat(r + 4) * cell, width: cell, height: cell)) } }
    for (r, c) in [(0, 0), (0, n - 7), (n - 7, 0)] {
        ctx.setLineWidth(cell); ctx.stroke(CGRect(x: CGFloat(c + 4) * cell + cell / 2, y: CGFloat(r + 4) * cell + cell / 2, width: 6 * cell, height: 6 * cell))
        ctx.fill(CGRect(x: CGFloat(c + 6) * cell, y: CGFloat(r + 6) * cell, width: 3 * cell, height: 3 * cell))
    }
    return ctx.makeImage()!
}
func barcode(_ text: String) -> CGImage {
    let f = CIFilter(name: "CICode128BarcodeGenerator")!; f.setValue(text.data(using: .ascii), forKey: "inputMessage"); f.setValue(10, forKey: "inputQuietSpace")
    let i = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 2, y: 2)); let bg = CIImage(color: .white).cropped(to: i.extent)
    return cg(i.composited(over: bg), i.extent)
}

let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
let base = drawQR(Style(), side: 300)
let cases: [(String, CGImage, String?)] = [
    ("01 기본", base, msg),
    ("02 둥근 모듈 + 둥근 눈", drawQR(Style(shape: .rounded, eye: .rounded), side: 300), msg),
    ("03 점 모듈(0.85) + 네모 눈", drawQR(Style(shape: .dot(0.85)), side: 300), msg),
    ("04 점 모듈 + 원 눈", drawQR(Style(shape: .dot(0.85), eye: .circle), side: 300), msg),
    ("05 작은 점(0.6) + 원 눈", drawQR(Style(shape: .dot(0.6), eye: .circle, level: "H"), side: 300), msg),
    ("06 물방울(이어진) + 둥근 눈", drawQR(Style(shape: .liquid, eye: .rounded), side: 300), msg),
    ("07 마름모 + 둥근 눈", drawQR(Style(shape: .diamond, eye: .rounded, level: "H"), side: 300), msg),
    ("08 하트 + 둥근 눈", drawQR(Style(shape: .heart, eye: .rounded, level: "H"), side: 300), msg),
    ("09 세로 선 모듈", drawQR(Style(shape: .vline, eye: .square, level: "H"), side: 300), msg),
    ("10 팔각 눈 + 점", drawQR(Style(shape: .dot(0.8), eye: .octagon, ink: rgb(14, 90, 70)), side: 300), msg),
    ("11 로고 25% (H)", drawQR(Style(shape: .rounded, eye: .rounded, logo: 0.25, level: "H"), side: 300), msg),
    ("12 로고 30% + 점 (H)", drawQR(Style(shape: .dot(0.8), eye: .rounded, logo: 0.3, level: "H"), side: 300), msg),
    ("13 눈까지 점(0.85)", drawQR(Style(shape: .dot(0.85), eye: .asModules, level: "H"), side: 300), msg),
    ("14 보라 · 흰 바탕", drawQR(Style(shape: .rounded, eye: .rounded, ink: rgb(120, 60, 230)), side: 300), msg),
    ("15 그라데이션 분홍→파랑", drawQR(Style(shape: .rounded, eye: .rounded, gradient: (rgb(230, 60, 160), rgb(40, 90, 230)), level: "H"), side: 300), msg),
    ("16 연두 모듈 · 파란 바탕", drawQR(Style(shape: .dot(0.85), eye: .rounded, ink: rgb(120, 240, 110), paper: rgb(70, 110, 240), level: "H"), side: 300), msg),
    ("17 주황 · 검은 바탕(반전)", drawQR(Style(shape: .rounded, eye: .circle, ink: rgb(240, 150, 100), paper: rgb(18, 18, 24)), side: 300), msg),
    ("18 저대비 회색 70%", drawQR(Style(ink: CGColor(gray: 0.7, alpha: 1)), side: 300), msg),
    ("19 다크 모드(밝은 회색 · 어두운 바탕)", drawQR(Style(ink: CGColor(gray: 0.82, alpha: 1), paper: CGColor(gray: 0.16, alpha: 1)), side: 300), msg),
    ("20 작게 70px", drawQR(Style(), side: 70, quiet: 2), msg),
    ("21 아주 작게 52px", drawQR(Style(), side: 52, quiet: 2), msg),
    ("22 화면 속 작게(1.6px/모듈, 흐릿)", resample(drawQR(Style(shape: .rounded, eye: .rounded), side: 600), 0.08), msg),
    ("23 흐림 3px", blur(base, 3), msg),
    ("24 JPEG 품질 15%", jpeg(drawQR(Style(shape: .dot(0.85), eye: .circle), side: 300), 0.15), msg),
    ("25 잡음 40%", noise(base, 0.4), msg),
    ("26 원근 기울임", perspective(base, 0.18), msg),
    ("27 회전 30°", rotate(base, 30), msg),
    ("28 큰 화면 속 90px", onScreen(base, at: CGPoint(x: 1200, y: 120), size: 90), msg),
    ("29 큰 화면 속 64px(점 모듈)", onScreen(drawQR(Style(shape: .dot(0.85), eye: .rounded), side: 300), at: CGPoint(x: 300, y: 700), size: 64), msg),
    ("30 한 장에 QR 둘", side2(base, drawQR(Style(shape: .dot(0.85), eye: .circle, ink: rgb(30, 60, 140)), side: 300)), msg),
    ("31 바코드 Code128", barcode("JUPJUP-2026"), "JUPJUP-2026"),
    ("32 둥근 + 로고 + 흐림 + JPEG", jpeg(blur(drawQR(Style(shape: .liquid, eye: .rounded, logo: 0.25, level: "H"), side: 260), 1.5), 0.3), msg),
    ("36 작은 점(0.5) + 원 눈", drawQR(Style(shape: .dot(0.5), eye: .circle, level: "H"), side: 300), msg),
    ("37 가는 세로 선 + 원 눈", drawQR(Style(shape: .vline, eye: .circle, level: "H"), side: 300), msg),
    ("38 로고 35% (H)", drawQR(Style(shape: .rounded, eye: .rounded, logo: 0.35, level: "H"), side: 300), msg),
    ("39 노랑 · 흰 바탕", drawQR(Style(shape: .rounded, eye: .rounded, ink: rgb(242, 194, 48)), side: 300), msg),
    ("40 큰 화면 속 60px(모듈 1.5px)", onScreen(base, at: CGPoint(x: 900, y: 400), size: 60), msg),
    ("41 흐림 5px", blur(base, 5), msg),
    ("42 잡음 70%", noise(base, 0.7), msg),
    ("43 원근 많이", perspective(base, 0.3), msg),
    ("44 다크 모드 + 점", drawQR(Style(shape: .dot(0.8), eye: .rounded, ink: CGColor(gray: 0.85, alpha: 1), paper: CGColor(gray: 0.13, alpha: 1), level: "H"), side: 300), msg),
    ("45 작은 점 + 작게 120px", drawQR(Style(shape: .dot(0.65), eye: .circle, level: "H"), side: 120, quiet: 2), msg),
    ("46 흰 점 · 검은 바탕", drawQR(Style(shape: .dot(0.75), eye: .circle, ink: .white, paper: .black, level: "H"), side: 300), msg),
    ("47 저대비 회색 80%", drawQR(Style(shape: .rounded, eye: .rounded, ink: CGColor(gray: 0.8, alpha: 1)), side: 300), msg),
    ("48 마름모 + 흐림 + JPEG", jpeg(blur(drawQR(Style(shape: .diamond, eye: .rounded, level: "H"), side: 260), 1.2), 0.25), msg),
    ("49 하트 + 로고 + 작게 140px", drawQR(Style(shape: .heart, eye: .rounded, logo: 0.25, level: "H"), side: 140, quiet: 2), msg),
    ("50 큰 화면 속 70px 하트", onScreen(drawQR(Style(shape: .heart, eye: .rounded, level: "H"), side: 300), at: CGPoint(x: 1400, y: 820), size: 70), msg),
    ("33 가짜 1(QR 모양만)", fake(seed: 1), nil),
    ("34 가짜 2", fake(seed: 7), nil),
    ("35 글만 있는 화면", onScreen(drawQR(Style(), side: 10), at: CGPoint(x: -500, y: -500), size: 1), nil),
]

let out = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-") ? CommandLine.arguments[1] : NSTemporaryDirectory()
let need = CommandLine.arguments.dropFirst(2).first.flatMap { Int($0) } ?? cases.filter { $0.2 != nil }.count
var ok = 0, wrong = 0, slow = 0.0
for (i, (name, img, want)) in cases.enumerated() {
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/qr\(i + 1).png"))
    let t = Date()
    let got = Recognizer.codes(img, thorough: !basic)
    let dt = Date().timeIntervalSince(t); slow = max(slow, dt)
    let pass: Bool
    if let want { pass = got.contains { $0.payload == want }; if pass { ok += 1 } }
    else { pass = got.isEmpty; if !pass { wrong += 1 } }
    print(pass ? "✓" : "✗", name, "(\(img.width)×\(img.height), \(Int(dt * 1000))ms)", pass ? "" : got.map(\.payload).joined(separator: " | "))
}
let total = cases.filter { $0.2 != nil }.count
print("\(ok)/\(total) 읽음 · 가짜에서 잘못 읽음 \(wrong) · 가장 느림 \(Int(slow * 1000))ms · 기준 \(need)\(basic ? " · 예전 방식" : "")")
exit(ok < need || wrong > 0 ? 1 : 0)
