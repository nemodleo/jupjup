import Foundation

// 화면 문구. 언어마다 Resources/Strings/<코드>.json 하나(키 61개, {n}{c}{r}{s} 자리표시).
// 메뉴에서 바꾸면 다시 켜지 않아도 바로 바뀐다. 파일에 없는 키는 영어로.

/// 화면 언어. "auto"는 시스템을 따른다
struct Lang: Hashable {
    let rawValue: String

    static let auto = Lang(rawValue: "auto")

    init(rawValue: String) { self.rawValue = rawValue }

    /// 저장된 값이 지금 없는 언어면 nil
    init?(saved: String) {
        guard saved == "auto" || Catalog.codes.contains(saved) else { return nil }
        self.rawValue = saved
    }

    /// 목록 순서: 로마자 → 그리스·키릴 → 오른쪽에서 쓰는 글자 → 인도·타이 → 한중일
    static var concrete: [Lang] { Catalog.codes.map(Lang.init(rawValue:)) }

    /// 그 언어로 쓴 이름
    var endonym: String { Catalog.raw(resolved.rawValue)["_name"] ?? resolved.rawValue }
    /// 아랍어·히브리어처럼 오른쪽에서 왼쪽으로 쓰는 언어
    var isRTL: Bool { Catalog.raw(resolved.rawValue)["_rtl"] == "true" }

    /// 자동이면 시스템 언어 순서에서 처음 맞는 것, 없으면 영어
    var resolved: Lang {
        guard self == .auto else { return self }
        for id in Locale.preferredLanguages {
            if let code = Catalog.match(id) { return Lang(rawValue: code) }
        }
        return Lang(rawValue: "en")
    }
}

enum Catalog {
    static let order = ["id", "ms", "ca", "cs", "da", "de", "en", "es", "fr", "hr", "it", "hu", "nl", "nb", "pl", "pt-BR", "ro",
                        "sk", "sl", "fi", "sv", "vi", "tr", "el", "kk", "ru", "uk", "he", "ar", "hi", "th", "ko", "ja", "zh-Hans", "zh-Hant"]

    /// 실제로 파일이 있는 언어만
    static let codes: [String] = order.filter { url($0) != nil }

    private static func url(_ code: String) -> URL? {
        Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Strings")
    }

    nonisolated(unsafe) private static var cache: [String: [String: String]] = [:]

    /// 그 언어 파일의 키→문구 (_rtl은 "true"/"false" 글로)
    static func raw(_ code: String) -> [String: String] {
        if let c = cache[code] { return c }
        var out: [String: String] = [:]
        if let u = url(code), let data = try? Data(contentsOf: u),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                if let s = v as? String { out[k] = s } else if let b = v as? Bool { out[k] = b ? "true" : "false" }
            }
        }
        cache[code] = out
        return out
    }

    /// "pt-PT", "zh-Hant-TW", "no", "en-GB" 같은 시스템 언어 → 가지고 있는 코드
    static func match(_ id: String) -> String? {
        let loc = Locale(identifier: id)
        guard let lang = loc.language.languageCode?.identifier else { return nil }
        if lang == "zh" {
            let script = loc.language.script?.identifier ?? (id.contains("TW") || id.contains("HK") || id.contains("MO") ? "Hant" : "Hans")
            return codes.contains("zh-\(script)") ? "zh-\(script)" : nil
        }
        if lang == "no" || lang == "nn" { return codes.contains("nb") ? "nb" : nil }
        if lang == "pt" { return codes.contains("pt-BR") ? "pt-BR" : nil }
        return codes.contains(lang) ? lang : nil
    }
}

struct Strings {
    var appName, tagline, pick, openAtLogin, joinLines, tables, language, auto, about, quit: String
    var pressKeys, change, changeShortcut, recordHint, needModifier: String
    var taken: (String) -> String
    var on, off: String
    var picked, working, workingSub, empty, emptySub, permission, permissionSub, undone, undoneSub, busy: String
    var textMeta: (Int, Int) -> String
    var tableMeta: (Int, Int) -> String
    var editedMeta: (Int) -> String
    var moreRows: (Int) -> String
    var asText, asTable, keepLines, joinOne, edit, undo, cancel, save, done: String
    var pickWindow, spaceDrag, dragSelect, spaceWindow: String
    var sameSpot: (String) -> String
    var escCancel: String
    var aboutTitle, aboutBody: String
    var back, uiText, ocrText, ocrAuto, ocrAutoSub, ocrManual, ocrManualSub, fallback, fallbackSub: String
    var nowSystem: (String) -> String
    var ocrMode, modeFast, modeAccurate, modeFastNote: String

    init(code: String) {
        let d = Catalog.raw(code), en = Catalog.raw("en")
        func v(_ k: String) -> String { d[k] ?? en[k] ?? k }
        func fill(_ k: String, _ pairs: [String: String]) -> String {
            pairs.reduce(v(k)) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        /// 한국어는 줄 수를 한·두·세…로
        func count(_ n: Int) -> String {
            guard code == "ko" else { return "\(n)" }
            let w = ["", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉", "열"]
            return n < w.count ? w[n] : "\(n)"
        }
        appName = v("appName"); tagline = v("tagline"); pick = v("pick"); openAtLogin = v("openAtLogin")
        joinLines = v("joinLines"); tables = v("tables"); language = v("language"); auto = v("auto")
        about = v("about"); quit = v("quit"); pressKeys = v("pressKeys"); change = v("change")
        changeShortcut = v("changeShortcut"); recordHint = v("recordHint"); needModifier = v("needModifier")
        taken = { fill("taken", ["s": $0]) }
        on = v("on"); off = v("off"); picked = v("picked"); working = v("working"); workingSub = v("workingSub")
        empty = v("empty"); emptySub = v("emptySub"); permission = v("permission"); permissionSub = v("permissionSub")
        undone = v("undone"); undoneSub = v("undoneSub"); busy = v("busy")
        textMeta = { n, c in n == 1 ? fill("textMetaOne", ["c": "\(c)"]) : fill("textMeta", ["n": count(n), "c": "\(c)"]) }
        tableMeta = { fill("tableMeta", ["r": "\($0)", "c": "\($1)"]) }
        editedMeta = { fill("editedMeta", ["c": "\($0)"]) }
        moreRows = { $0 == 1 ? v("moreRowsOne") : fill("moreRows", ["n": "\($0)"]) }
        asText = v("asText"); asTable = v("asTable"); keepLines = v("keepLines"); joinOne = v("joinOne")
        edit = v("edit"); undo = v("undo"); cancel = v("cancel"); save = v("save"); done = v("done")
        pickWindow = v("pickWindow"); spaceDrag = v("spaceDrag"); dragSelect = v("dragSelect"); spaceWindow = v("spaceWindow")
        sameSpot = { fill("sameSpot", ["s": $0]) }
        escCancel = v("escCancel"); aboutTitle = v("aboutTitle"); aboutBody = v("aboutBody")
        back = v("back"); uiText = v("uiText"); ocrText = v("ocrText"); ocrAuto = v("ocrAuto"); ocrAutoSub = v("ocrAutoSub")
        ocrManual = v("ocrManual"); ocrManualSub = v("ocrManualSub"); fallback = v("fallback"); fallbackSub = v("fallbackSub")
        nowSystem = { fill("nowSystem", ["s": $0]) }
        ocrMode = v("ocrMode"); modeFast = v("modeFast"); modeAccurate = v("modeAccurate"); modeFastNote = v("modeFastNote")
    }
}

@MainActor
enum L {
    private static var cache: [String: Strings] = [:]

    /// 지금 고른 언어의 문구
    static var s: Strings { table(Settings.shared.language) }

    static func table(_ lang: Lang) -> Strings {
        let code = lang.resolved.rawValue
        if let t = cache[code] { return t }
        let t = Strings(code: code)
        cache[code] = t
        return t
    }
}
