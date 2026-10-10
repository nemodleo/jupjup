import AppKit
import SwiftUI
import CoreText

// 묵묵과 같은 바탕: 먹 · 한지 · 낙관 주홍 하나. 시스템 밝기 설정을 따른다.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Ink {
    static let mook = NSColor(hex: 0x1F1D1A)
    static let hanji = NSColor(hex: 0xE4DDCF)
    static let hanjiLight = NSColor(hex: 0xF6F2EA)
    static let seal = NSColor(hex: 0xC4553A)

    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static let panel = dyn(hanjiLight, mook)
    static let text = dyn(mook, hanji)
    static let sub = dyn(NSColor(hex: 0x4A443C), NSColor(hex: 0xCFC7B9))
    static let faint = dyn(NSColor(hex: 0x6B645A), NSColor(hex: 0x9C9488))
    static let rule = dyn(NSColor(hex: 0x1F1D1A, alpha: 0.10), NSColor(hex: 0xE4DDCF, alpha: 0.10))
    static let fill = dyn(NSColor(hex: 0x1F1D1A, alpha: 0.06), NSColor(hex: 0xE4DDCF, alpha: 0.08))
    /// 주홍 글씨: 어두운 바탕에선 밝게 띄워 읽히게
    static let sealText = dyn(NSColor(hex: 0xB04A31), NSColor(hex: 0xE9876E))
    static let border = dyn(NSColor(hex: 0x1F1D1A, alpha: 0.08), NSColor(hex: 0xE4DDCF, alpha: 0.06))
}

extension Color {
    static let inkPanel = Color(nsColor: Ink.panel)
    static let inkText = Color(nsColor: Ink.text)
    static let inkSub = Color(nsColor: Ink.sub)
    static let inkFaint = Color(nsColor: Ink.faint)
    static let inkRule = Color(nsColor: Ink.rule)
    static let inkFill = Color(nsColor: Ink.fill)
    static let inkBorder = Color(nsColor: Ink.border)
    static let seal = Color(nsColor: Ink.seal)
    static let sealText = Color(nsColor: Ink.sealText)
}

/// 글꼴. 본문(메뉴·미리보기·버튼·숫자)은 시스템 서체, 얼굴(앱 이름·알림 제목·사전 풀이)만 언어별 명조.
/// 얼굴 — 한국어: 본명조 가늘게(없으면 함렛 가늘게) · 라틴 문자 언어: Cormorant Garamond(없으면 애플 New York)
/// · 그 밖의 문자(키릴·그리스·아랍·타이·한자 등): 시스템 서체. 한글용 자간은 한국어에만.
/// 시스템 설정 › 손쉬운 사용 › 디스플레이 › "동작 줄이기"를 따른다: 도는 점선·튀는 도장·들썩이는 줄을 멈춘다
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

enum Fonts {
    /// Resources/Fonts 안의 글꼴 파일을 모두 앱 안에서만 쓰도록 등록
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    /// 본문
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func nsFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    enum Script { case korean, latin, other }

    /// 라틴 문자로 쓰는 화면 언어
    static let latinCodes: Set<String> = ["en", "de", "fr", "es", "it", "pt-BR", "nl", "ca", "ro", "da", "nb", "sv", "fi",
                                          "pl", "cs", "sk", "sl", "hr", "hu", "tr", "id", "ms", "vi"]

    @MainActor static var script: Script {
        let code = Settings.shared.language.resolved.rawValue
        if code == "ko" { return .korean }
        return latinCodes.contains(code) ? .latin : .other
    }

    private static func has(_ family: String) -> Bool { NSFontManager.shared.availableMembers(ofFontFamily: family) != nil }
    static let koreanFace = has("Noto Serif KR") ? "Noto Serif KR" : "Hahmlet"
    static let latinFace: String? = has("Cormorant Garamond") ? "Cormorant Garamond" : nil

    /// 얼굴 서체. 굵게 쓰지 않는다(한글 300, 라틴 500). 코모란트는 글자가 작아 보여 조금 키운다
    @MainActor static func face(_ size: CGFloat) -> Font {
        switch script {
        case .korean: return .custom(koreanFace, size: size).weight(.light)
        case .latin:
            if let f = latinFace { return .custom(f, size: size * 1.15).weight(.medium) }
            return .system(size: size, weight: .regular, design: .serif)
        case .other: return .system(size: size, weight: .medium)
        }
    }

    /// 얼굴 서체 자간: 한글만 살짝 띄운다
    @MainActor static func faceTracking(_ size: CGFloat) -> CGFloat { script == .korean ? size * 0.05 : 0 }
}

/// 함렛으로 쓴 글의 폭(pt). 언어마다 길이가 달라 메뉴·알림 폭을 정할 때 쓴다
@MainActor
func textWidth(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
    ceil(NSAttributedString(string: s, attributes: [.font: Fonts.nsFont(size, weight)]).size().width)
}

/// 메뉴 막대 글리프. 선택 모서리 + 글 세 줄. 고르는 중엔 줄이 비고, 주운 직후엔 가운데 줄이 들린다.
enum Glyph {
    case idle, picking, picked

    var image: NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let corners = NSBezierPath()
            corners.lineWidth = 1.4
            for (a, b, c) in [((2.5, 6.0), (2.5, 2.5), (6.0, 2.5)), ((12.0, 2.5), (15.5, 2.5), (15.5, 6.0)),
                              ((15.5, 12.0), (15.5, 15.5), (12.0, 15.5)), ((6.0, 15.5), (2.5, 15.5), (2.5, 12.0))] {
                corners.move(to: NSPoint(x: a.0, y: a.1))
                corners.line(to: NSPoint(x: b.0, y: b.1))
                corners.line(to: NSPoint(x: c.0, y: c.1))
            }
            corners.stroke()
            switch self {
            case .picking: break
            case .idle:
                NSRect(x: 5.5, y: 6.3, width: 7, height: 1.4).fill()
                NSRect(x: 5.5, y: 8.6, width: 7, height: 1.4).fill()
                NSRect(x: 5.5, y: 10.9, width: 4.5, height: 1.4).fill()
            case .picked:
                NSRect(x: 5.5, y: 6.3, width: 7, height: 1.4).fill()
                NSRect(x: 5.5, y: 10.9, width: 4.5, height: 1.4).fill()
                let t = NSAffineTransform()
                t.translateX(by: 10.7, yBy: 8.3)
                t.rotate(byDegrees: -8)
                let lifted = NSBezierPath(rect: NSRect(x: -3.7, y: -0.7, width: 7.5, height: 1.5))
                lifted.transform(using: t as AffineTransform)
                lifted.fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "줍줍"
        return img
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var joinLines: Bool { didSet { d.set(joinLines, forKey: "joinLines") } }
    @Published var tables: Bool { didSet { d.set(tables, forKey: "tables") } }
    @Published var shortcut: Shortcut {
        didSet {
            d.set(Int(shortcut.keyCode), forKey: "hotKeyCode")
            d.set(Int(shortcut.carbonMods), forKey: "hotKeyMods")
        }
    }
    @Published var language: Lang {
        didSet {
            d.set(language.rawValue, forKey: "language")
            Reporting.signal("language.changed", ["language": language.resolved.rawValue])
        }
    }
    /// 읽을 글자: 직접 고르기 / 고른 Vision 코드(목록 순서) / 못 읽으면 다른 글자도
    @Published var ocrManual: Bool { didSet { d.set(ocrManual, forKey: "ocrManual") } }
    @Published var ocrLanguages: [String] { didSet { d.set(ocrLanguages, forKey: "ocrLanguages") } }
    @Published var ocrFallback: Bool { didSet { d.set(ocrFallback, forKey: "ocrFallback") } }
    /// 인식 모드: 빠르게(라이브 텍스트) / 정확하게(Vision, 기본)
    @Published var fastMode: Bool {
        didSet {
            d.set(fastMode, forKey: "fastMode")
            Reporting.signal("mode.changed", ["mode": fastMode ? "fast" : "accurate"])
        }
    }
    /// 오류·사용 통계 보내기(기본 켬). 끄면 그 자리에서 멈춘다
    @Published var reports: Bool {
        didSet {
            d.set(reports, forKey: "reports")
            if reports { Reporting.start() } else { Reporting.stop() }
        }
    }
    /// 메뉴에서 새 단축키를 기다리는 중
    @Published var recording = false
    /// 녹음 결과 안내(쓸 수 없는 조합 등). 잠깐 보였다 사라진다
    @Published var shortcutNote: String?

    private init() {
        d.register(defaults: ["joinLines": false, "tables": true, "reports": true,
                              // 노치 뒤로 숨지 않게 오른쪽 끝 가까이 둔다(우연·묵묵과 같은 방법)
                              "NSStatusItem Preferred Position jupjup": 360])
        joinLines = d.bool(forKey: "joinLines")
        tables = d.bool(forKey: "tables")
        language = Lang(saved: d.string(forKey: "language") ?? "auto") ?? .auto
        ocrManual = d.bool(forKey: "ocrManual")
        ocrLanguages = d.stringArray(forKey: "ocrLanguages") ?? []
        ocrFallback = d.object(forKey: "ocrFallback") as? Bool ?? true
        fastMode = d.bool(forKey: "fastMode")
        reports = d.bool(forKey: "reports")
        if d.object(forKey: "hotKeyCode") != nil {
            shortcut = Shortcut(keyCode: UInt32(d.integer(forKey: "hotKeyCode")), carbonMods: UInt32(d.integer(forKey: "hotKeyMods")))
        } else {
            shortcut = .standard
        }
    }
}

/// 앱 아이콘을 작은 UI 표지로 그린다(알림·메뉴·고르기 안내줄). 디자인 캔버스와 같은 180 격자.
enum AppMark {
    enum State { case picked, working, empty }

    /// phase 0…1: 주홍 줄이 들린 정도(줍는 중 애니메이션)
    /// yDown: 좌표가 이미 위→아래인 곳(SwiftUI Canvas)이면 true
    static func draw(in ctx: CGContext, rect: CGRect, state: State, phase: CGFloat = 0, yDown: Bool = false) {
        let s = rect.width / 180
        ctx.saveGState()
        // 위→아래 좌표로 맞춰 캔버스 SVG 숫자를 그대로 쓴다
        if yDown {
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: s, y: s)
        } else {
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: s, y: -s)
        }
        ctx.translateBy(x: -10, y: -10)
        if state == .empty { ctx.setAlpha(0.45) }
        let small = rect.width <= 28
        ctx.addPath(CGPath(roundedRect: CGRect(x: 10, y: 10, width: 180, height: 180), cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.setFillColor(Ink.hanjiLight.cgColor)
        ctx.fillPath()
        ctx.setStrokeColor(Ink.mook.cgColor)
        ctx.setLineWidth(small ? 12 : 8)
        ctx.setLineCap(.square)
        for p in [[(50, 72), (50, 52), (70, 52)], [(130, 52), (150, 52), (150, 72)], [(150, 128), (150, 148), (130, 148)], [(70, 148), (50, 148), (50, 128)]] {
            ctx.move(to: CGPoint(x: p[0].0, y: p[0].1))
            ctx.addLine(to: CGPoint(x: p[1].0, y: p[1].1))
            ctx.addLine(to: CGPoint(x: p[2].0, y: p[2].1))
        }
        ctx.strokePath()
        if state != .empty {
            let lh: CGFloat = small ? 14 : 10
            ctx.setFillColor(Ink.mook.cgColor)
            ctx.fill(CGRect(x: 72, y: 88 - lh / 2, width: 58, height: lh))
            ctx.fill(CGRect(x: 72, y: 126 - lh / 2, width: 40, height: lh))
            let lift = state == .working ? phase : 0
            ctx.translateBy(x: 117, y: 101 - 6 * lift)
            ctx.rotate(by: -(6 + 8 * lift) * .pi / 180)
            ctx.setFillColor(Ink.seal.cgColor)
            ctx.fill(CGRect(x: -31, y: -(lh + 1) / 2, width: 62, height: lh + 1))
        }
        ctx.restoreGState()
    }

    static func image(size: CGFloat, state: State = .picked) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(in: ctx, rect: r, state: state) }
            return true
        }
    }
}

/// SwiftUI용 표지. 줍는 중이면 주홍 줄이 1.2초마다 들렸다 내려앉는다.
struct AppMarkView: View {
    var state: AppMark.State = .picked
    var size: CGFloat = 24

    var body: some View {
        TimelineView(.animation(paused: state != .working || Motion.reduced)) { tl in
            Canvas { gc, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                let phase = state == .working && !Motion.reduced ? CGFloat((sin(t * 2 * .pi / 1.2) + 1) / 2) : 0
                gc.withCGContext { AppMark.draw(in: $0, rect: CGRect(origin: .zero, size: sz), state: state, phase: phase, yDown: true) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(state == .working ? L.s.working : L.s.appName)
    }
}
