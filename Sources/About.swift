import AppKit
import SwiftUI

/// "줍줍에 대하여": 사전 한 쪽처럼. 표제어 줍다 크게, 풀이 한 줄, 설명 한 줄, 맨 아래 판·글꼴 (캔버스 8번 보드)
@MainActor
final class AboutController {
    private var window: NSWindow?

    func show() {
        if window == nil { build() }
        guard let w = window else { return }
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = Ink.panel
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.title = L.s.aboutTitle
        let host = NSHostingView(rootView: AboutView())
        w.contentView = host
        w.setContentSize(host.fittingSize)
        window = w
    }
}

struct AboutView: View {
    static let repo = URL(string: "https://github.com/nemodleo/jupjup")!
    static let privacy = URL(string: "https://github.com/nemodleo/jupjup/blob/main/PRIVACY.md")!
    /// 연락 메일. 저장소의 CONTACT 한 곳에서 빌드 때 Info.plist로 들어온다(`make contact EMAIL=…`로 바꿈)
    static let contact = (Bundle.main.infoDictionary?["JJContactEmail"] as? String).flatMap { $0.contains("@") ? $0 : nil }

    var body: some View {
        let paras = L.s.aboutBody.components(separatedBy: "\n\n")
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // 표제어는 언제나 한글. 한국어가 아닐 때만 읽는 법을 곁들인다
                Text("줍다").font(.custom(Fonts.koreanFace, size: 40).weight(.light)).tracking(3.2).foregroundStyle(Color.inkText)
                if Settings.shared.language.resolved.rawValue != "ko" {
                    Text("jup·da").font(Fonts.face(15)).foregroundStyle(Color.inkFaint)
                }
                Spacer(minLength: 0)
                Image(nsImage: AppMark.image(size: 56)).resizable().frame(width: 28, height: 28).opacity(0.9)
            }
            if let first = paras.first {
                Text(first).font(Fonts.face(15)).tracking(Fonts.faceTracking(15)).lineSpacing(3).foregroundStyle(Color.inkText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(paras.dropFirst().dropLast().enumerated()), id: \.offset) { _, p in
                Text(p).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Color.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if paras.count > 2, let last = paras.last {
                Text(last).font(.system(size: 11)).foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let mail = Self.contact, let url = URL(string: "mailto:\(mail)") {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(mail).font(.system(size: 11.5)).foregroundStyle(Color.sealText).underline(color: Color.sealText.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Spacer()
                ObButton(title: "GitHub") { NSWorkspace.shared.open(Self.repo) }
                ObButton(title: "PRIVACY.md") { NSWorkspace.shared.open(Self.privacy) }
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 28, leading: 24, bottom: 18, trailing: 24))
        .frame(width: 320)
        .background(Color.inkPanel)
        .environment(\.layoutDirection, Settings.shared.language.isRTL ? .rightToLeft : .leftToRight)
    }
}
