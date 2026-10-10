// 표 알아보기 POC 확인: swiftc Sources/Recognizer.swift tools/recognize_test.swift
// 인자로 이미지 경로를 주면 그 이미지를, 없으면 직접 그린 표·문단을 읽는다.
import AppKit

func render(_ w: CGFloat, _ h: CGFloat, _ draw: () -> Void) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}
let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15)]

func report(_ name: String, _ img: CGImage) {
    let r = Recognizer.recognize(img)
    print("── \(name)")
    if let t = r.table {
        print("표 \(t.rows.count)행 \(t.columnCount)열")
        print(t.tsv.replacingOccurrences(of: "\t", with: " │ "))
    } else {
        print("글")
        print(r.text)
    }
}

if CommandLine.arguments.count > 1 {
    for path in CommandLine.arguments.dropFirst() {
        let img = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        report(path, img)
    }
    exit(0)
}

let table = [["이름", "학과", "학년", "점수"],
             ["김민지", "컴퓨터공학과", "3", "92.5"],
             ["Lee Jun", "경영학과", "2", "88"],
             ["박서연", "전기정보공학부", "4", "100"],
             ["최우진", "물리학과", "1", "76.25"]]
let xs: [CGFloat] = [20, 150, 320, 400]
report("표 (제목 줄 포함)", render(520, 230) {
    ("2026년 2학기 성적표" as NSString).draw(at: NSPoint(x: 20, y: 195), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 17)])
    for (i, row) in table.enumerated() {
        for (j, cell) in row.enumerated() {
            (cell as NSString).draw(at: NSPoint(x: xs[j], y: 155 - CGFloat(i) * 32), withAttributes: font)
        }
    }
    NSColor.gray.setStroke()
    for i in 0...5 { NSBezierPath.strokeLine(from: NSPoint(x: 10, y: 182 - CGFloat(i) * 32), to: NSPoint(x: 500, y: 182 - CGFloat(i) * 32)) }
})

report("문단", render(560, 140) {
    let s = "최소제곱법은 잔차의 제곱합을 최소로 만드는 계수를 찾는 방법이다. 이때 오차항은 서로 독립이며 평균이 0, 분산이 일정하다고 가정한다. The quick brown fox jumps over the lazy dog."
    (s as NSString).draw(in: NSRect(x: 20, y: 10, width: 520, height: 120), withAttributes: font)
})
