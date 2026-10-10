// 표 인식 채점: HTML 표를 WebKit으로 그려 칸 단위로 맞춰 봄. main.swift로 복사해서
// swiftc -O Sources/Recognizer.swift main.swift -framework WebKit -o t && ./t <그림 저장 폴더>
import AppKit
import WebKit

// 실제 웹페이지처럼 HTML 표를 WebKit으로 그려 줍줍 표 인식을 칸 단위로 채점
struct Case { let name: String; let html: String; let expect: [[String]]? } // expect nil = 표가 아니어야 함

func table(_ rows: [[String]], style: String, head: Bool = true) -> String {
    var h = "<table>"
    for (i, r) in rows.enumerated() {
        h += "<tr>" + r.map { i == 0 && head ? "<th>\($0)</th>" : "<td>\($0)</td>" }.joined() + "</tr>"
    }
    return "<html><head><meta charset='utf-8'><style>body{margin:24px;font:14px -apple-system,'Apple SD Gothic Neo',sans-serif;background:#fff;color:#222}\(style)</style></head><body>\(h)</table></body></html>"
}
let grades = [["이름", "학과", "학년", "점수"], ["김민지", "컴퓨터공학과", "3", "92.5"], ["Lee Jun", "경영학과", "2", "88"], ["박서연", "전기정보공학부", "4", "100"], ["최우진", "물리학과", "1", "76.25"]]
let money = [["항목", "1분기", "2분기", "3분기", "합계"], ["매출", "1,204,500", "1,388,000", "1,512,300", "4,104,800"], ["원가", "702,100", "811,450", "880,900", "2,394,450"], ["영업이익", "502,400", "576,550", "631,400", "1,710,350"]]
let wiki = [["Country", "Capital", "Population (2024)", "Area (km²)"], ["South Korea", "Seoul", "51,717,590", "100,363"], ["Japan", "Tokyo", "123,975,371", "377,975"], ["New Zealand", "Wellington", "5,213,944", "268,021"], ["Iceland", "Reykjavík", "393,600", "103,000"]]
let gaps = [["요일", "1교시", "2교시", "3교시"], ["월", "미적분", "", "물리"], ["화", "", "영어", "영어"], ["수", "화학", "미적분", ""]]
let wrap = [["단계", "설명", "담당"], ["기획", "요구사항을 모으고 우선순위를 정한다", "PM"], ["설계", "화면 흐름과 데이터 구조를 그린다", "디자이너"], ["개발", "기능을 만들고 테스트한다", "개발자"]]

let cases: [Case] = [
    Case(name: "1 성적표(테두리)", html: table(grades, style: "table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:6px 14px;text-align:left}th{background:#f2f2f2}"), expect: grades),
    Case(name: "2 엑셀식(숫자 오른쪽)", html: table(money, style: "table{border-collapse:collapse;font-variant-numeric:tabular-nums}td,th{border:1px solid #d0d0d0;padding:3px 10px}td{text-align:right}td:first-child{text-align:left}th{background:#e8f0e8}"), expect: money),
    Case(name: "3 위키식(영문·여러 단어)", html: table(wiki, style: "table{border-collapse:collapse;background:#f8f9fa}td,th{border:1px solid #a2a9b1;padding:4px 8px}th{background:#eaecf0}td:nth-child(n+3){text-align:right}"), expect: wiki),
    Case(name: "4 테두리 없음·넓은 간격", html: table(money, style: "td,th{padding:4px 26px 4px 0;text-align:left}th{border-bottom:1px solid #333}"), expect: money),
    Case(name: "5 빈 칸 섞임", html: table(gaps, style: "table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:6px 18px;min-width:60px}"), expect: gaps),
    Case(name: "6 칸 안 줄바꿈", html: table(wrap, style: "table{border-collapse:collapse;width:420px}td,th{border:1px solid #bbb;padding:6px 10px;vertical-align:top}td:nth-child(2){width:220px}"), expect: wrap),
    Case(name: "7 표 아님: 두 단 글", html: "<html><head><meta charset='utf-8'><style>body{margin:24px;font:14px -apple-system,'Apple SD Gothic Neo';columns:2;column-gap:40px;width:640px;line-height:1.6}</style></head><body>최소제곱법은 잔차의 제곱합을 최소로 만드는 계수를 찾는 방법이다. 이때 오차항은 서로 독립이며 평균이 0, 분산이 일정하다고 가정한다. 결정계수는 모형이 설명하는 변동의 비율이며 설명변수를 추가하면 줄어들지 않는다. 그래서 수정된 결정계수를 함께 본다. 다중공선성이 크면 계수의 표준오차가 커진다.</body></html>", expect: nil),
    Case(name: "8 표 아님: 그냥 문단", html: "<html><head><meta charset='utf-8'><style>body{margin:24px;font:14px -apple-system,'Apple SD Gothic Neo';width:560px;line-height:1.6}</style></head><body>회귀 분석(regression analysis)에서 R² 값은 0.87이고, p-value는 0.003이다. Python의 statsmodels로 계산했으며 표본은 1,204명이다.</body></html>", expect: nil),
]

final class Runner: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 360))
    var i = 0
    var total = 0, right = 0
    override init() { super.init(); web.navigationDelegate = self }
    func next() {
        guard i < cases.count else {
            let pct = Double(right) * 100 / Double(max(total, 1))
            let threshold = Double(CommandLine.arguments.dropFirst(2).first ?? "95") ?? 95
            print(String(format: "\n전체 칸 정확도 %d/%d (%.0f%%) · 기준 %.0f%%", right, total, pct, threshold))
            exit(pct < threshold ? 1 : 0) // 기준 아래면 실패(CI)
        }
        web.loadHTMLString(cases[i].html, baseURL: nil)
    }
    func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = 1520 // 레티나 2배
            w.takeSnapshot(with: cfg) { [self] img, _ in
                let c = cases[i]
                let cg = img!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/case\(i + 1).png"))
                let r = Recognizer.recognize(cg, prefer: ["ko-KR", "en-US"])
                print("── \(c.name)")
                if let t = r.table {
                    // 위쪽 빈 줄(여백)은 빼고 비교
                    print("  표로 판단: \(t.rows.count)행 \(t.columnCount)열")
                    for row in t.rows { print("   " + row.map { $0.isEmpty ? "·" : $0 }.joined(separator: " │ ")) }
                    if let e = c.expect {
                        var ok = 0, n = 0
                        for (ri, er) in e.enumerated() { for (ci, ec) in er.enumerated() {
                            n += 1
                            let got = ri < t.rows.count && ci < t.rows[ri].count ? t.rows[ri][ci] : "∅"
                            if got.replacingOccurrences(of: " ", with: "") == ec.replacingOccurrences(of: " ", with: "") { ok += 1 }
                        } }
                        total += n; right += ok
                        print("  칸 일치 \(ok)/\(n)" + (t.rows.count == e.count && t.columnCount == e[0].count ? "" : "  (모양 다름: 기대 \(e.count)행 \(e[0].count)열)"))
                    } else { print("  ✗ 표가 아닌데 표로 판단") }
                } else {
                    print(c.expect == nil ? "  ✓ 글로 판단" : "  ✗ 표를 못 알아봄")
                    if let e = c.expect { total += e.flatMap { $0 }.count }
                    print("   " + r.text.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(120))
                }
                i += 1; next()
            }
        }
    }
}
let app = NSApplication.shared
let runner = Runner()
runner.next()
app.run()
