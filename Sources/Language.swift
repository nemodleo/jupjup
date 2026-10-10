import SwiftUI

// 언어 화면(디자인 캔버스 5번). 메뉴의 "언어" 줄을 누르면 메뉴가 이 화면으로 넘어간다.
// 화면 글자: 자동 / 각 언어 · 읽을 글자: 자동 / 직접 고르기(체크한 언어만 위에서부터, 다른 글자 찾기 스위치)

/// 메뉴가 어느 화면인지. 메뉴를 열 때마다 처음 화면으로
@MainActor
final class MenuState: ObservableObject {
    enum Page { case main, language, uiLanguage }
    @Published var page: Page = .main
}

/// 직접 고르기 목록: Vision 코드와 그 언어로 쓴 이름. 같은 글자 변형(아랍어 두 종류, 광둥어 간·번)은 하나로
enum OCRChoice {
    static let all: [(code: String, name: String)] = [
        ("ko-KR", "한국어"), ("en-US", "English"), ("ja-JP", "日本語"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
        ("yue-Hant", "粵語"), ("fr-FR", "Français"), ("de-DE", "Deutsch"), ("es-ES", "Español"), ("it-IT", "Italiano"),
        ("pt-BR", "Português"), ("vi-VT", "Tiếng Việt"), ("ru-RU", "Русский"), ("uk-UA", "Українська"), ("th-TH", "ไทย"),
        ("ar-SA", "العربية"),
    ].filter { OCRLanguages.supported.contains($0.0) }

    /// 체크한 것을 목록 순서대로(위에서부터 = 읽는 순서)
    static func ordered(_ picked: [String]) -> [String] {
        all.map(\.code).filter { picked.contains($0) }
    }
}

struct LanguagePage: View {
    @ObservedObject var settings: Settings
    let back: () -> Void
    let openUILanguages: () -> Void
    @State private var overUI = false

    var body: some View {
        let t = L.s
        VStack(alignment: .leading, spacing: 1) {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.backward").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.inkSub)
                    Text(t.language).font(Fonts.font(13, .semibold)).foregroundStyle(Color.inkText)
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.back)

            rule
            // 화면 글자: 지금 상태 한 줄, 누르면 목록
            Button(action: openUILanguages) {
                HStack(spacing: 6) {
                    Text(t.uiText).font(Fonts.font(12.5)).foregroundStyle(Color.inkSub)
                    Spacer()
                    Text(settings.language == .auto ? "\(t.auto) · \(Lang.auto.endonym)" : settings.language.endonym)
                        .font(Fonts.font(11)).foregroundStyle(Color.inkFaint).lineLimit(1)
                    Image(systemName: "chevron.forward").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.inkFaint)
                }
                .padding(.horizontal, 8).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(overUI ? Color.inkFill : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { overUI = $0 }

            rule
            header(t.ocrText)
            ChoiceRow(mark: .radio(!settings.ocrManual), title: t.ocrAuto, sub: settings.ocrManual ? nil : t.ocrAutoSub,
                      selected: !settings.ocrManual) { settings.ocrManual = false }
            ChoiceRow(mark: .radio(settings.ocrManual), title: t.ocrManual, sub: settings.ocrManual ? t.ocrManualSub : nil,
                      selected: settings.ocrManual) {
                if !settings.ocrManual && settings.ocrLanguages.isEmpty { settings.ocrLanguages = OCRLanguages.primary() }
                settings.ocrManual = true
            }
            if settings.ocrManual {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(OCRChoice.all, id: \.code) { c in
                        let order = OCRChoice.ordered(settings.ocrLanguages)
                        let n = order.firstIndex(of: c.code).map { $0 + 1 }
                        ChoiceRow(mark: .check(n != nil), title: c.name, trailing: n.map(String.init), height: 24) {
                            toggle(c.code)
                        }
                    }
                }
                .padding(.leading, 6)
                .overlay(alignment: .leading) { Rectangle().fill(Color.inkRule).frame(width: 1) }
                .padding(.leading, 18).padding(.trailing, 4).padding(.vertical, 2)
                rule
                ChoiceRow(mark: .check(settings.ocrFallback), title: t.fallback, sub: t.fallbackSub, selected: false) {
                    settings.ocrFallback.toggle()
                }
            }
        }
    }

    /// 마지막 하나는 끌 수 없다(읽을 언어가 없으면 안 되니까)
    private func toggle(_ code: String) {
        var picked = settings.ocrLanguages
        if let i = picked.firstIndex(of: code) {
            guard picked.count > 1 else { return }
            picked.remove(at: i)
        } else {
            picked.append(code)
        }
        settings.ocrLanguages = OCRChoice.ordered(picked)
    }

    private var rule: some View {
        Rectangle().fill(Color.inkRule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(Fonts.font(11)).tracking(1.6).foregroundStyle(Color.inkFaint)
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 3)
    }
}

/// 라디오·체크 한 줄. 고른 줄은 살짝 밝은 바탕
struct ChoiceRow: View {
    enum Mark { case radio(Bool), check(Bool) }
    let mark: Mark
    let title: String
    var sub: String?
    var trailing: String?
    var selected = false
    var height: CGFloat?
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                markView
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Fonts.font(12.5)).foregroundStyle(selected ? Color.inkText : Color.inkSub)
                    if let sub {
                        Text(sub).font(Fonts.font(11)).foregroundStyle(Color.inkFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(Color.inkFaint) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, sub == nil ? 0 : 5)
            .frame(minHeight: height ?? (sub == nil ? 26 : 30))
            .background(RoundedRectangle(cornerRadius: 6).fill(selected || over ? Color.inkFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
    }

    @ViewBuilder private var markView: some View {
        switch mark {
        case .radio(let on):
            ZStack {
                Circle().strokeBorder(on ? Color.seal : Color.inkFaint, lineWidth: on ? 1.3 : 1.1)
                if on { Circle().fill(Color.seal).frame(width: 6.5, height: 6.5) }
            }
            .frame(width: 13, height: 13)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        case .check(let on):
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(on ? Color.seal : .clear)
                RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Color.seal : Color.inkFaint, lineWidth: 1.2)
                if on {
                    Path { p in p.move(to: CGPoint(x: 3.2, y: 6.9)); p.addLine(to: CGPoint(x: 5.7, y: 9.3)); p.addLine(to: CGPoint(x: 10.1, y: 4.1)) }
                        .stroke(Color(nsColor: Ink.hanjiLight), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 13, height: 13)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
    }
}

/// 화면 글자 목록: 자동 + 가지고 있는 언어 전부(각 언어 이름). 목록만 스크롤
struct UILanguagePage: View {
    @ObservedObject var settings: Settings
    let back: () -> Void

    var body: some View {
        let t = L.s
        VStack(alignment: .leading, spacing: 1) {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.backward").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.inkSub)
                    Text(t.uiText).font(Fonts.font(13, .semibold)).foregroundStyle(Color.inkText)
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.back)

            Rectangle().fill(Color.inkRule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            ChoiceRow(mark: .radio(settings.language == .auto), title: t.auto, sub: t.nowSystem(Lang.auto.endonym),
                      selected: settings.language == .auto) { settings.language = .auto }
            Rectangle().fill(Color.inkRule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Lang.concrete, id: \.self) { l in
                            ChoiceRow(mark: .radio(settings.language == l), title: l.endonym,
                                      selected: settings.language == l, height: 24) { settings.language = l }
                                .id(l)
                        }
                    }
                }
                .frame(height: 400)
                .onAppear { if settings.language != .auto { proxy.scrollTo(settings.language, anchor: .center) } }
            }
        }
    }
}
