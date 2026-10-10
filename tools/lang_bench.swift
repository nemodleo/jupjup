// 다국어 인식 채점: 12개 언어 문장을 그려 Recognizer.recognize로 읽고, 원문 글자가 얼마나 살아 있는지 잰다.
// tools/run_tests.sh가 main.swift로 복사해 컴파일한다. 언어 하나라도 기준(기본 95%) 아래면 종료 코드 1.
import AppKit

func render(_ text: String) -> CGImage {
    let w = 700.0, h = 200.0
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    (text as NSString).draw(in: NSRect(x: 16, y: 10, width: w - 32, height: h - 20), withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

/// 원문 글자(공백 제외) 중 결과에 들어 있는 비율(%)
func kept(_ a: String, _ b: String) -> Int {
    let A = Array(a.filter { !$0.isWhitespace }), B = Set(b.filter { !$0.isWhitespace })
    return A.isEmpty ? 0 : A.filter { B.contains($0) }.count * 100 / A.count
}

let samples: [(String, String)] = [
    ("한국어", "최소제곱법은 잔차의 제곱합을 최소로 만드는 계수를 찾는 방법이다. 이때 오차항은 서로 독립이며 평균이 0, 분산이 일정하다고 가정한다."),
    ("한영섞임", "회귀 분석(regression analysis)에서 R 값은 0.87이고, p-value는 0.003이다. Python의 statsmodels로 계산했다."),
    ("영어", "The least squares method finds coefficients that minimize the sum of squared residuals."),
    ("프랑스어", "La méthode des moindres carrés trouve les coefficients qui minimisent la somme des carrés des résidus."),
    ("베트남어", "Phương pháp bình phương tối thiểu tìm các hệ số làm cực tiểu tổng bình phương phần dư."),
    ("독일어", "Die Methode der kleinsten Quadrate bestimmt Koeffizienten, die die Summe der quadrierten Residuen minimieren."),
    ("일본어", "最小二乗法は残差の二乗和を最小にする係数を求める方法である。誤差は互いに独立であると仮定する。"),
    ("중국어", "最小二乘法是寻找使残差平方和最小的系数的方法。误差被假定为相互独立。"),
    ("번체", "最小平方法是尋找使殘差平方和最小的係數的方法。誤差被假定為相互獨立。"),
    ("러시아어", "Метод наименьших квадратов находит коэффициенты, минимизирующие сумму квадратов остатков."),
    ("태국어", "วิธีกำลังสองน้อยที่สุดใช้หาค่าสัมประสิทธิ์ที่ทำให้ผลรวมกำลังสองของส่วนเหลือมีค่าน้อยที่สุด"),
    ("아랍어", "طريقة المربعات الصغرى تجد المعاملات التي تقلل مجموع مربعات البواقي."),
]
let threshold = Int(CommandLine.arguments.dropFirst().first ?? "95") ?? 95
let prefer = ["ko-KR", "en-US"] // 한국어 사용자 기준으로 고정(러너의 시스템 언어에 좌우되지 않게)
var worst = 100
for (name, text) in samples {
    let t = Date()
    let r = Recognizer.recognize(render(text), prefer: prefer)
    let k = kept(text, r.text)
    worst = min(worst, k)
    print(String(format: "%@\t%d%%\t%.2fs%@", name, k, Date().timeIntervalSince(t), k < threshold ? "\t← 기준 아래" : ""))
}
print("가장 낮은 언어 \(worst)% · 기준 \(threshold)%")
exit(worst < threshold ? 1 : 0)
