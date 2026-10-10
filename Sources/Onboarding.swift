import AppKit
import SwiftUI

// 첫 실행 안내 창(디자인 캔버스 9번). 할 일은 둘: 단축키 확인, 화면 기록 권한.
// 권한 없이 단축키를 누르면 이 창이 다시 열린다. 둘 다 되면 "첫 줍기 해 보기".

@MainActor
final class OnboardingModel: ObservableObject {
    /// 단축키를 다른 앱이 쓰고 있어 등록하지 못함
    @Published var conflict = false
    @Published var permission = OnboardingModel.hasPermission()

    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }
    func refresh() { permission = Self.hasPermission() }
}

@MainActor
final class OnboardingController {
    let model = OnboardingModel()
    private var window: NSWindow?
    private var poll: Timer?

    var onChangeShortcut: ((NSWindow) -> Void)?
    var onTry: (() -> Void)?

    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded") }
    }

    func show() {
        model.refresh()
        if window == nil { build() }
        guard let w = window else { return }
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
    }

    func close() {
        if !Self.done { Reporting.signal("onboarding.done", ["permission": model.permission ? "yes" : "no"]) }
        Self.done = true
        poll?.invalidate()
        poll = nil
        window?.orderOut(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = Ink.panel
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.title = L.s.appName
        let view = OnboardingView(model: model, settings: .shared, actions: .init(
            changeShortcut: { [weak self] in if let self, let w = self.window { self.onChangeShortcut?(w) } },
            openSettings: {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                NSWorkspace.shared.open(url)
            },
            relaunch: { Self.relaunch() },
            later: { [weak self] in self?.close() },
            try: { [weak self] in self?.close(); self?.onTry?() }))
        Reporting.signal("onboarding.shown")
        let host = NSHostingView(rootView: view)
        w.contentView = host
        w.setContentSize(host.fittingSize)
        window = w
    }

    /// 권한을 켠 뒤에는 다시 열어야 ScreenCaptureKit이 화면을 준다
    static func relaunch() {
        Self.done = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }
}

struct OnboardingView: View {
    struct Actions {
        var changeShortcut: () -> Void
        var openSettings: () -> Void
        var relaunch: () -> Void
        var later: () -> Void
        var `try`: () -> Void
    }

    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: Settings
    let actions: Actions

    private var ready: Bool { model.permission && !model.conflict }

    var body: some View {
        let t = L.s
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: AppMark.image(size: 88)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.appName).font(Fonts.face(22)).tracking(Fonts.faceTracking(22)).foregroundStyle(Color.inkText)
                    Text(t.tagline).font(.system(size: 12)).foregroundStyle(Color.inkFaint)
                }
            }
            Text(t.obIntro).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Color.inkSub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14).padding(.bottom, 10)

            // 1 · 단축키
            step(mark: model.conflict ? .warn : .check(true), title: t.obShortcut,
                 body: model.conflict ? t.obShortcutTaken(settings.shortcut.text) : t.obShortcutOK) {
                if settings.recording {
                    Text(t.pressKeys).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.seal)
                        .padding(.horizontal, 6).frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.seal, lineWidth: 1))
                } else {
                    HStack(spacing: 3) { ForEach(Array(settings.shortcut.caps.enumerated()), id: \.offset) { KeyCap($0.element) } }
                        .environment(\.layoutDirection, .leftToRight)
                }
                ObButton(title: t.change, strong: model.conflict, action: actions.changeShortcut)
            } sub: {
                if let note = settings.shortcutNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(Color.sealText)
                }
            }

            // 2 · 화면 기록 권한
            step(mark: .check(model.permission), title: t.obPermission,
                 body: model.permission ? t.obPermissionOn : t.obPermissionOff) {
                if model.permission {
                    Text(t.obOn).font(.system(size: 12)).foregroundStyle(Color.sealText)
                } else {
                    ObButton(title: t.obOpenSettings, strong: true, action: actions.openSettings)
                }
            } sub: {
                if !model.permission {
                    HStack(spacing: 8) {
                        Text(t.obRelaunchNote).font(.system(size: 12)).foregroundStyle(Color.inkFaint)
                        ObButton(title: t.obRelaunch, action: actions.relaunch)
                    }
                    .padding(.top, 4)
                }
            }

            // 3 · 오류·사용 통계 (기본 켬, 체크를 눌러 끔)
            step(mark: .check(settings.reports), title: t.obReports, body: t.obReportsBody, toggle: { settings.reports.toggle() }) {
                Text(settings.reports ? t.obReportsOn : t.obReportsOff).font(.system(size: 12)).foregroundStyle(Color.inkFaint)
            } sub: { EmptyView() }

            HStack(spacing: 8) {
                Spacer()
                ObButton(title: ready ? t.obClose : t.obLater, action: actions.later)
                ObButton(title: ready ? "\(t.obTry) \(settings.shortcut.text)" : t.obTry, strong: true, action: actions.try)
                    .opacity(ready ? 1 : 0.4)
                    .disabled(!ready)
            }
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 26, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 400)
        .background(Color.inkPanel)
        .environment(\.layoutDirection, settings.language.isRTL ? .rightToLeft : .leftToRight)
    }

    enum Mark { case check(Bool), warn }

    private func step<R: View, S: View>(mark: Mark, title: String, body: String, toggle: (() -> Void)? = nil,
                                        @ViewBuilder right: () -> R, @ViewBuilder sub: () -> S) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 누를 수 있는 건 3단계(리포트)뿐. disabled로 두면 흐려지므로 hit test만 막는다
            Button { toggle?() } label: { markView(mark).padding(.top, 1).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .allowsHitTesting(toggle != nil)
                .accessibilityLabel(title)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.inkText)
                    Spacer()
                    HStack(spacing: 6) { right() }
                }
                Text(body).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                sub()
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.inkRule).frame(height: 1) }
    }

    @ViewBuilder private func markView(_ m: Mark) -> some View {
        switch m {
        case .check(let on):
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(on ? Color.seal : .clear)
                RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Color.seal : Color.inkFaint, lineWidth: 1.2)
                if on {
                    Path { p in p.move(to: CGPoint(x: 4, y: 8.5)); p.addLine(to: CGPoint(x: 7, y: 11.5)); p.addLine(to: CGPoint(x: 12.5, y: 5)) }
                        .stroke(Color(nsColor: Ink.hanjiLight), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 16, height: 16)
        case .warn:
            Text("!").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(nsColor: Ink.hanjiLight))
                .frame(width: 16, height: 16).background(Circle().fill(Color.seal))
        }
    }
}

struct ObButton: View {
    let title: String
    var strong = false
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? Color(nsColor: Ink.hanjiLight) : Color.inkText)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(strong ? Color.seal.opacity(over ? 0.85 : 1) : Color.inkFill.opacity(over ? 1.6 : 1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
    }
}
