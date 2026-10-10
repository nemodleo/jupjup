import Vision
import VisionKit
import NaturalLanguage
import CoreGraphics
import Foundation

// 글자 인식 + 줄 묶기 + 표 알아보기. UI와 떨어져 있어 tools/ 테스트에서 그대로 컴파일한다.

/// 인식된 글 조각. 좌표는 이미지 픽셀, 원점은 왼쪽 아래(Vision과 같음).
struct Piece {
    var rect: CGRect
    var text: String
}

struct Table {
    var rows: [[String]]
    var columnCount: Int { rows.map(\.count).max() ?? 0 }

    /// 엑셀·넘버스·구글 시트에 붙이면 칸이 나뉘는 탭 구분 글
    var tsv: String {
        rows.map { $0.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t") }
            .joined(separator: "\n")
    }

    /// 노션·페이지·구글 문서용
    var html: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let body = rows.map { "<tr>" + $0.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined()
        return "<meta charset=\"utf-8\"><table>\(body)</table>"
    }
}

/// QR·바코드 하나. 내용은 글로 붙고, 종류는 알림 덧말에 쓴다
struct Code {
    var rect: CGRect
    var payload: String
    /// QR·데이터매트릭스 같은 2차원 코드면 true, 줄무늬 바코드면 false
    var isQR: Bool
}

struct Recognized {
    /// 위→아래 줄, 각 줄은 왼→오른쪽 조각
    var lines: [[Piece]]
    var table: Table?
    /// 같이 읽힌 QR·바코드(내용은 lines 끝에 한 줄씩 들어 있다)
    var codes: [Code] = []

    var text: String {
        lines.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 줄바꿈을 지우고 한 문단으로 잇는다. 줄 끝 하이픈(영문 단어 끊김)은 붙여 쓴다.
    var joinedText: String {
        var out = ""
        for line in lines.map({ $0.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if out.isEmpty { out = line; continue }
            if out.hasSuffix("-"), let last = out.dropLast().last, last.isLetter, last.isASCII {
                out.removeLast()
                out += line
            } else {
                out += " " + line
            }
        }
        return out
    }

    var isEmpty: Bool { text.isEmpty }
}

enum Recognizer {
    /// QR·바코드. 글자 인식과 별개 요청이라 빠르게·정확하게 어느 모드에서나 돈다. 같은 내용은 한 번만
    static func codes(_ image: CGImage) -> [Code] {
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let flat: Set<VNBarcodeSymbology> = [.ean8, .ean13, .upce, .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
                                             .code93, .code93i, .code128, .i2of5, .i2of5Checksum, .itf14, .codabar]
        var seen = Set<String>()
        return (req.results ?? []).compactMap { o in
            guard let s = o.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, seen.insert(s).inserted else { return nil }
            let b = o.boundingBox
            return Code(rect: CGRect(x: b.minX * w, y: b.minY * h, width: b.width * w, height: b.height * h),
                        payload: s, isQR: !flat.contains(o.symbology))
        }
        .sorted { $0.rect.maxY > $1.rect.maxY } // 위에 있는 것부터
    }

    /// 코드 내용을 글 맨 앞에 한 줄씩 둔다(QR을 골랐으면 그 내용이 주인공, 옆 글자는 덤).
    /// 글자 인식이 코드 밑 숫자 같은 걸 이미 읽었으면 그 줄은 빼서 겹치지 않게 한다
    static func merge(_ r: Recognized, codes: [Code]) -> Recognized {
        guard !codes.isEmpty else { return r }
        var out = r
        let payloads = Set(codes.map(\.payload))
        out.codes = codes
        out.lines = codes.map { [Piece(rect: $0.rect, text: $0.payload)] }
            + r.lines.filter { !payloads.contains($0.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)) }
        return out
    }

    /// Vision은 목록 맨 앞 언어로 글자 모델을 하나 고르고, 그 모델이 모르는 문자는 읽지 못한다
    /// (한국어가 앞이면 일본어·중국어는 0자, 프랑스어 악센트·베트남어 성조도 빠짐). 자동 감지는 섞인 글을 망친다(실측).
    /// 그래서:
    /// 1차 — 내 언어를 앞에 두고 읽는다. 결과가 내 언어로 판별되고 충분하면 끝(대부분 여기서 끝, 1회).
    /// 라틴 — 결과가 프랑스어·베트남어처럼 다른 라틴 문자 언어면, 그 언어를 앞에 두고 한 번 더(악센트 살림).
    /// 넓게 — 1차가 엉터리면(글자가 거의 없거나 판별 불가) 문자권마다 맨 앞을 바꿔 읽고 점수가 높은 결과.
    /// 점수 = 읽은 글자 수 × 신뢰도. 엉터리 결과는 신뢰도가 높아도 글자가 "-=" 처럼 몇 개 없다.
    static func recognize(_ image: CGImage, prefer: [String] = OCRLanguages.primary(), fallback: Bool = true) -> Recognized {
        let first = read(image, languages: OCRLanguages.firstPass(prefer), autoDetect: false)
        let lang = OCRLanguages.detect(first.result.text)
        let mine = Set(prefer.map { OCRLanguages.base($0) })

        if let lang, mine.contains(lang), first.confidence >= 0.6, score(first) >= 3 { return first.result }

        if let lang, let latin = OCRLanguages.latinCode(lang), fallback || prefer.contains(latin) {
            let again = read(image, languages: [latin] + OCRLanguages.latin, autoDetect: false)
            return score(again) >= score(first) * 0.95 ? again.result : first.result
        }

        var best = first
        // 다른 글자 찾기를 끄면, 직접 고른 언어 중 라틴 문자가 아닌 것만 맨 앞에 세워 본다
        let leads = fallback ? OCRLanguages.otherScripts(excluding: prefer)
                             : prefer.dropFirst().filter { !OCRLanguages.latin.contains($0) }
        for lead in leads {
            let r = read(image, languages: [lead, "en-US"], autoDetect: false)
            if score(r) > score(best) * 1.05 { best = r }
        }
        return best.result
    }

    /// 읽은 글자(문자) 수 × 평균 신뢰도
    static func score(_ r: (result: Recognized, confidence: Double)) -> Double {
        Double(r.result.text.filter(\.isLetter).count) * r.confidence
    }

    /// Vision 한 번 실행. 결과와 글자 수로 무게를 단 평균 신뢰도(0…1)
    static func read(_ image: CGImage, languages: [String], autoDetect: Bool) -> (result: Recognized, confidence: Double) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = languages
        req.automaticallyDetectsLanguage = autoDetect
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let obs = req.results ?? []

        func px(_ r: CGRect) -> CGRect { CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h) }

        var weight = 0.0, total = 0.0
        let pieces = obs.compactMap { o -> Piece? in
            guard let c = o.topCandidates(1).first else { return nil }
            let n = Double(c.string.count)
            weight += Double(c.confidence) * n
            total += n
            return Piece(rect: px(o.boundingBox), text: c.string)
        }
        // 표 판단용: 한 관측 안에서도 낱말 사이가 크게 벌어지면 칸으로 쪼갠다
        let wordPieces = obs.flatMap { o -> [Piece] in
            guard let c = o.topCandidates(1).first else { return [] }
            return Self.words(of: c, fallback: px(o.boundingBox)).map { Piece(rect: px($0.rect), text: $0.text) }
        }
        let result = Recognized(lines: group(pieces), table: detectTable(group(wordPieces)))
        return (result, total > 0 ? weight / total : 0)
    }

    /// 후보 글을 공백 단위 낱말로 나누고 각 낱말의 상자를 구한다(정규화 좌표).
    private static func words(of c: VNRecognizedText, fallback: CGRect) -> [Piece] {
        let s = c.string
        var out: [Piece] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            guard let start = s[idx...].firstIndex(where: { !$0.isWhitespace }) else { break }
            let end = s[start...].firstIndex(where: \.isWhitespace) ?? s.endIndex
            let box = (try? c.boundingBox(for: start..<end))?.boundingBox
            out.append(Piece(rect: box ?? fallback, text: String(s[start..<end])))
            idx = end
        }
        // 상자를 못 구한 낱말이 섞이면 쪼개기를 포기하고 통째로 쓴다
        if out.contains(where: { $0.rect == fallback }) { return [Piece(rect: fallback, text: s)] }
        return out
    }

    /// 높이가 겹치는 조각끼리 한 줄로 묶는다.
    static func group(_ pieces: [Piece]) -> [[Piece]] {
        let sorted = pieces.sorted { $0.rect.midY > $1.rect.midY }
        var lines: [[Piece]] = []
        var centers: [CGFloat] = []
        var heights: [CGFloat] = []
        for p in sorted {
            if let c = centers.last, let lh = heights.last, abs(c - p.rect.midY) < min(lh, p.rect.height) * 0.5 {
                lines[lines.count - 1].append(p)
                let n = CGFloat(lines[lines.count - 1].count)
                centers[centers.count - 1] = c + (p.rect.midY - c) / n
                heights[heights.count - 1] = max(lh, p.rect.height)
            } else {
                lines.append([p])
                centers.append(p.rect.midY)
                heights.append(p.rect.height)
            }
        }
        return lines.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }

    /// 열 사이의 "세로 통로" 찾기: 표는 열과 열 사이가 모든 행에 걸쳐 비어 있다.
    /// 1) 모든 줄의 낱말 상자를 가로로 겹쳐 보고, 거의 모든 줄에서 비어 있는 넓은 구간을 통로로 본다
    ///    (위쪽 제목처럼 통로를 가로지르는 줄이 일부 있어도 되게, 5줄 이상이면 20%까지 허용)
    /// 2) 통로 사이가 열. 낱말은 가운데 x로 열에 넣는다. 통로를 가로지르는 줄(제목 등)은 첫 칸에 통째로
    /// 3) 칸 안 줄바꿈: 첫 칸이 비고 줄 간격이 좁은 줄은 위 행에 이어 붙인다
    /// 4) 칸마다 긴 문장(중앙값 26자 초과)이면 두 단 글로 보고 표가 아니라고 한다
    static func detectTable(_ lines: [[Piece]]) -> Table? {
        guard lines.count >= 2 else { return nil }
        let heights = lines.flatMap { $0.map(\.rect.height) }.sorted()
        let lineH = heights[heights.count / 2]
        let minX = lines.flatMap { $0.map(\.rect.minX) }.min() ?? 0
        let maxX = lines.flatMap { $0.map(\.rect.maxX) }.max() ?? 0
        let width = Int(ceil(maxX - minX)) + 1
        guard width > 1 else { return nil }

        // 1) 가로 위치마다 덮는 줄 수
        var cover = [Int](repeating: 0, count: width)
        for line in lines {
            var mark = [Bool](repeating: false, count: width)
            for p in line {
                let a = max(0, Int(p.rect.minX - minX)), b = min(width - 1, Int(p.rect.maxX - minX))
                if a <= b { for x in a...b { mark[x] = true } }
            }
            for x in 0..<width where mark[x] { cover[x] += 1 }
        }
        let allowed = lines.count >= 5 ? lines.count / 5 : 0
        var gutters: [ClosedRange<CGFloat>] = []
        var runStart: Int?
        for x in 0...width {
            let empty = x < width && cover[x] <= allowed
            if empty, runStart == nil { runStart = x }
            if !empty, let st = runStart {
                if CGFloat(x - st) >= lineH * 0.5, st > 0, x < width { gutters.append((CGFloat(st) + minX)...(CGFloat(x) + minX)) }
                runStart = nil
            }
        }
        guard !gutters.isEmpty else { return nil }
        let cols = gutters.count + 1
        // 열 구간: 통로와 통로 사이. 낱말은 가장 많이 겹치는 열로(가운데 정렬 제목이 통로에 걸쳐도 맞는 열로)
        let edges = [minX] + gutters.flatMap { [$0.lowerBound, $0.upperBound] } + [maxX]
        let bands = (0..<cols).map { edges[$0 * 2]...edges[$0 * 2 + 1] }
        func column(_ r: CGRect) -> Int {
            var best = 0, bestOverlap = -CGFloat.infinity
            for (i, b) in bands.enumerated() {
                let o = min(r.maxX, b.upperBound) - max(r.minX, b.lowerBound)
                let score = o > 0 ? o : -min(abs(r.midX - b.lowerBound), abs(r.midX - b.upperBound))
                if score > bestOverlap { bestOverlap = score; best = i }
            }
            return best
        }

        // 2) 줄 → 행
        var rows: [[String]] = []
        var rowTops: [CGFloat] = [], rowBottoms: [CGFloat] = []
        for line in lines {
            var row = Array(repeating: "", count: cols)
            // 제목처럼 통로를 가로지르는 줄: 낱말 하나가 통로를 덮거나, 낱말 사이가 평범한 띄어쓰기뿐인데 통로를 건너는 줄
            let lineMin = line.map(\.rect.minX).min() ?? 0, lineMax = line.map(\.rect.maxX).max() ?? 0
            let widestGap = zip(line, line.dropFirst()).map { $1.rect.minX - $0.rect.maxX }.max() ?? 0
            let crosses = gutters.contains { lineMin < $0.lowerBound && lineMax > $0.upperBound }
            let spans = line.contains { p in gutters.contains { g in p.rect.minX < g.lowerBound && p.rect.maxX > g.upperBound } }
                || (crosses && widestGap < lineH * 0.6)
            if spans {
                row[0] = line.map(\.text).joined(separator: " ")
            } else {
                for p in line {
                    let i = column(p.rect)
                    row[i] = row[i].isEmpty ? p.text : row[i] + " " + p.text
                }
            }
            rows.append(row)
            rowTops.append(line.map(\.rect.maxY).max() ?? 0)
            rowBottoms.append(line.map(\.rect.minY).min() ?? 0)
        }

        // 3) 칸 안 줄바꿈 이어 붙이기
        let gaps = zip(rowBottoms, rowTops.dropFirst()).map { $0 - $1 }.sorted()
        let typicalGap = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
        var merged: [[String]] = []
        for (i, row) in rows.enumerated() {
            let gap = i > 0 ? rowBottoms[i - 1] - rowTops[i] : .infinity
            let filled = row.filter { !$0.isEmpty }.count
            if let last = merged.last, row[0].isEmpty, filled <= max(1, cols / 2), gap < max(typicalGap * 0.75, lineH * 0.45) {
                merged[merged.count - 1] = zip(last, row).map { a, b in b.isEmpty ? a : (a.isEmpty ? b : a + " " + b) }
            } else {
                merged.append(row)
            }
        }

        // 표다운지 확인
        let multi = merged.filter { $0.filter { !$0.isEmpty }.count >= 2 }
        guard multi.count >= 2, Double(multi.count) >= Double(merged.count) * 0.5 else { return nil }
        let lengths = merged.flatMap { $0 }.filter { !$0.isEmpty }.map(\.count).sorted()
        guard lengths[lengths.count / 2] <= 26 else { return nil } // 4) 두 단 글
        return Table(rows: merged)
    }
}

// MARK: 미리 깨우기
extension Recognizer {
    /// 앱을 켤 때 모든 문자권 모델을 한 번씩 돌려 둔다
    static func warmUp() {
        Task.detached(priority: .background) {
            let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            guard let img = ctx?.makeImage() else { return }
            // 문자권마다 모델을 처음 불러올 때 3~4초 걸린다 → 켤 때 뒤에서 한 번씩 미리
            _ = read(img, languages: OCRLanguages.firstPass(OCRLanguages.primary()), autoDetect: false)
            _ = read(img, languages: OCRLanguages.latin, autoDetect: false)
            for lead in OCRLanguages.scriptLeads { _ = read(img, languages: [lead, "en-US"], autoDetect: false) }
        }
    }
}

// MARK: 인식 언어 고르기

enum OCRLanguages {
    /// 1차 결과의 평균 신뢰도가 이 이상이면 다른 문자권은 시도하지 않는다
    static var acceptAbove = 0.95

    /// 이 맥의 Vision이 읽을 수 있는 언어
    static let supported: [String] = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        return (try? r.supportedRecognitionLanguages()) ?? ["en-US"]
    }()

    /// 라틴 문자 언어(한 모델로 함께 읽힘). 베트남어 성조·프랑스어 악센트를 살리려면 목록에 있어야 함
    static let latin = ["en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "vi-VT"]

    /// 문자권마다 맨 앞에 세울 대표 언어
    static let scriptLeads = ["ko-KR", "ja-JP", "zh-Hans", "zh-Hant", "ru-RU", "th-TH", "ar-SA"]

    /// 시스템 언어 순서(+ 따로 고른 화면 언어)를 Vision 코드로 맞추고 영어를 더한다
    static func primary(uiLanguage: String? = nil) -> [String] {
        var out: [String] = []
        for id in ([uiLanguage].compactMap { $0 } + Locale.preferredLanguages) {
            if let code = match(id), !out.contains(code) { out.append(code) }
        }
        if !out.contains("en-US") { out.append("en-US") }
        return out
    }

    /// 1차 목록: 내 언어들 뒤에 라틴 문자 언어 전부
    static func firstPass(_ prefer: [String]) -> [String] {
        (prefer + latin).reduce(into: [String]()) { if !$0.contains($1) && supported.contains($1) { $0.append($1) } }
    }

    /// "ko-KR" → "ko", "zh-Hans" → "zh-Hans"
    static func base(_ code: String) -> String {
        code.hasPrefix("zh") || code.hasPrefix("yue") ? code : String(code.prefix { $0 != "-" })
    }

    /// 읽은 글의 언어(판별이 분명할 때만). 글자가 너무 적으면 nil
    static func detect(_ text: String) -> String? {
        guard text.filter(\.isLetter).count >= 3 else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p >= 0.6 else { return nil }
        return lang.rawValue
    }

    /// 영어 말고 Vision이 읽을 수 있는 라틴 문자 언어면 그 코드
    static func latinCode(_ lang: String) -> String? {
        guard lang != "en" else { return nil }
        return latin.first { base($0) == lang && supported.contains($0) }
    }

    /// 1차에서 맨 앞이 아니었던 다른 문자권 대표들
    static func otherScripts(excluding prefer: [String]) -> [String] {
        scriptLeads.filter { $0 != prefer.first && supported.contains($0) }
    }

    /// "ko-KR", "zh-Hant-TW", "pt-PT" 같은 시스템 언어 → Vision 코드
    static func match(_ id: String) -> String? {
        if supported.contains(id) { return id }
        let loc = Locale(identifier: id)
        guard let lang = loc.language.languageCode?.identifier else { return nil }
        if lang == "zh" || lang == "yue" {
            let script = loc.language.script?.identifier ?? (id.contains("TW") || id.contains("HK") ? "Hant" : "Hans")
            let code = "\(lang)-\(script)"
            return supported.contains(code) ? code : nil
        }
        return supported.first { $0.hasPrefix(lang + "-") }
    }
}

// MARK: 예비 길: 라이브 텍스트(VisionKit)
// Vision이 오류를 내거나 모든 문자권을 시도하고도 글자를 못 찾았을 때만 쓴다.
// 글자 위치를 주지 않아 표 판단은 하지 않는다(줄 단위 글만).
@MainActor
enum LiveText {
    private static let analyzer = ImageAnalyzer()

    static func read(_ image: CGImage) async -> Recognized? {
        guard ImageAnalyzer.isSupported,
              let a = try? await analyzer.analyze(image, orientation: .up, configuration: .init(.text)) else { return nil }
        let lines = a.transcript.split(separator: "\n", omittingEmptySubsequences: true)
            .map { [Piece(rect: .zero, text: String($0).trimmingCharacters(in: .whitespaces))] }
            .filter { !($0.first?.text.isEmpty ?? true) }
        return lines.isEmpty ? nil : Recognized(lines: lines, table: nil)
    }

    /// 빠르게 모드일 때 엔진을 미리 깨운다(처음 한 번은 몇 초 걸림)
    static func warmUp() {
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        guard let img = ctx?.makeImage() else { return }
        Task { _ = await read(img) }
    }
}
