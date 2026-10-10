import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

// 줍줍: 단축키(기본 ⌘⇧2) → 영역 고르기 → 글자 인식 → 클립보드에 담아 둠. 표는 표로.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let capture = CaptureController()
    private let toast = ToastController()
    private let marker = SelectionMarker()
    private var cpu = CPUMeter()
    private var menuPanel: ToastPanel?
    private let menuState = MenuState()
    /// 메뉴를 열기 전 앞에 있던 앱. 메뉴는 마우스 올림(바꾸기·강조)을 받으려고 잠깐 줍줍을 앞으로 세운다
    private var appBeforeMenu: NSRunningApplication?
    private var menuKeyMonitor: Any?
    private var outsideMonitor: Any?
    private let hotKey = HotKeyCenter()
    private var recordMonitor: Any?
    private var askedPermission = false
    private var captureStart = Date()
    private let onboarding = OnboardingController()

    func applicationDidFinishLaunching(_ note: Notification) {
        Fonts.register()
        if CommandLine.arguments.contains("-benchocr") { benchOCR(); return }
        if let i = CommandLine.arguments.firstIndex(of: "-snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.render(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        _ = Settings.shared
        statusItem.autosaveName = "jupjup"
        if let b = statusItem.button {
            b.image = Glyph.idle.image
            b.target = self
            b.action = #selector(toggleMenu)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        capture.onPicked = { [weak self] image, rect in
            guard let self else { return }
            // 인식을 시작하기 전에 '줍는 중'부터 그린다. 맥이 바쁘면 경고도 함께
            self.captureStart = Date()
            self.marker.show(rect)
            self.toast.show(.working, busyCPU: self.cpu.busyPercent())
            self.recognize(image)
        }
        capture.onCancel = { [weak self] in self?.setGlyph(.idle); Reporting.signal("capture.cancelled") }
        capture.onError = { [weak self] _ in
            guard let self else { return }
            self.setGlyph(.idle)
            Reporting.error("capture.failed", ["reason": "permission"])
            // 권한이 없으면 안내 창을 2단계(권한)로 연다. 시스템 권한 창은 앱을 켠 동안 한 번만
            self.onboarding.show()
            if !self.askedPermission {
                self.askedPermission = true
                CGRequestScreenCaptureAccess()
            }
        }
        Reporting.start()
        Recognizer.warmUp()
        if Settings.shared.fastMode { LiveText.warmUp() }
        enableLoginOnFirstRun()
        hotKey.onPress = { [weak self] in self?.startCapture() }
        if !hotKey.register(Settings.shared.shortcut) {
            // 저장된 조합을 다른 앱이 쓰고 있으면 기본값으로. 그것도 안 되면 충돌(TextSniper 등)
            Settings.shared.shortcut = .standard
            onboarding.model.conflict = !hotKey.register(.standard)
        }

        onboarding.onChangeShortcut = { [weak self] w in self?.startRecording(in: w) }
        onboarding.onTry = { [weak self] in self?.startCapture() }
        if !OnboardingController.done {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.onboarding.show() }
        } else if onboarding.model.conflict {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.toast.show(.conflict) }
        }
    }

    // 노치 뒤에 숨어 안 보일 때: 앱을 다시 열면 메뉴가 열린다
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMenu()
        return false
    }

    private func setGlyph(_ g: Glyph) { statusItem.button?.image = g.image }

    /// 처음 설치해 켰을 때 한 번만 "맥을 켜면 함께 열기"를 켠다. 나중에 메뉴에서 끄면 다시 켜지 않는다
    private func enableLoginOnFirstRun() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "loginItemSetUp") else { return }
        d.set(true, forKey: "loginItemSetUp")
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    /// 시험: 실제 캡쳐 때처럼 '줍는 중'을 띄우고 큰 글 이미지를 인식하면서, 메인 스레드가 가장 오래 멈춘 시간을 잰다.
    /// `Jupjup -benchocr` → 표준 출력에 결과, 끝나면 종료
    private func benchOCR() {
        let w = 1100.0, h = 800.0
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let text = String(repeating: "최소제곱법은 잔차의 제곱합을 최소로 만드는 계수를 찾는 방법이다. The quick brown fox jumps over the lazy dog. ", count: 22)
        (text as NSString).draw(in: NSRect(x: 20, y: 20, width: w - 40, height: h - 40), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        NSGraphicsContext.restoreGraphicsState()
        let image = rep.cgImage!

        var last = Date(), worst = 0.0, ticks = 0
        let watch = Timer(timeInterval: 0.01, repeats: true) { _ in
            let now = Date(); worst = max(worst, now.timeIntervalSince(last)); last = now; ticks += 1
        }
        RunLoop.main.add(watch, forMode: .common)
        let start = Date()
        marker.show(CGRect(x: 200, y: 200, width: 500, height: 300))
        toast.show(.working, busyCPU: cpu.busyPercent())
        DispatchQueue.main.async {
            Task.detached(priority: .userInitiated) {
                // `-fast`면 빠르게(라이브 텍스트) 모드로 잰다
                let r: Recognized
                if CommandLine.arguments.contains("-fast"), let live = await LiveText.read(image) { r = live } else { r = Recognizer.recognize(image) }
                await MainActor.run {
                    watch.invalidate()
                    print(String(format: "인식 %.2fs · 메인 스레드 최장 멈춤 %.0fms · 틱 %d · %d줄 · 글자 %d", Date().timeIntervalSince(start), worst * 1000, ticks, r.lines.count, r.text.filter { !$0.isWhitespace }.count))
                    exit(0)
                }
            }
        }
    }

    // MARK: 줍기

    func startCapture() {
        if !capture.isActive { cpu.mark() } // 고르는 동안의 CPU 사용률을 잰다
        let returnTo = menuPanel?.isVisible == true ? appBeforeMenu : nil // 메뉴에서 눌렀으면 캡쳐 뒤 메뉴 전 앱으로
        closeMenu(restoreFocus: false)
        marker.dismiss(animated: false)
        setGlyph(.picking)
        Reporting.signal("capture.started", ["mode": Settings.shared.fastMode ? "fast" : "accurate"])
        capture.start(returnTo: returnTo)
    }

    /// Vision으로 읽는다(글자 위치까지 → 표 알아보기). '줍는 중'이 화면에 그려진 다음에 시작한다.
    private func recognize(_ image: CGImage) {
        DispatchQueue.main.async {
            // 화면 언어를 따로 골랐으면 그 언어를 인식에서도 맨 앞에
            let st = Settings.shared
            let prefer = st.ocrManual && !st.ocrLanguages.isEmpty
                ? OCRChoice.ordered(st.ocrLanguages)
                : OCRLanguages.primary(uiLanguage: st.language == .auto ? nil : st.language.rawValue)
            let fallback = !st.ocrManual || st.ocrFallback
            let fast = st.fastMode
            Task.detached(priority: .userInitiated) {
                var result: Recognized
                if fast, let live = await LiveText.read(image) {
                    result = live // 빠르게: 라이브 텍스트(못 쓰거나 못 읽으면 아래 Vision으로)
                } else {
                    result = Recognizer.recognize(image, prefer: prefer, fallback: fallback)
                    // 정확하게: Vision이 못 읽었으면 라이브 텍스트로 한 번 더
                    if result.isEmpty, !fast, let live = await LiveText.read(image) { result = live }
                }
                let done = result
                await MainActor.run { self.deliver(done) }
            }
        }
    }

    private func deliver(_ result: Recognized) {
        marker.finish(ok: !result.isEmpty)
        let mode = Settings.shared.fastMode ? "fast" : "accurate"
        if result.isEmpty {
            Reporting.signal("capture.empty", ["mode": mode])
        } else {
            Reporting.signal("capture.done", ["mode": mode, "lines": Reporting.bucket(result.lines.count),
                                              "chars": Reporting.bucket(result.text.count),
                                              "table": result.table == nil ? "no" : "yes",
                                              "seconds": Reporting.seconds(Date().timeIntervalSince(captureStart))])
        }
        if result.isEmpty {
            setGlyph(.idle)
            toast.show(.empty)
            return
        }
        let backup = ClipboardBackup()
        toast.show(.picked, result: result, backup: backup)
        setGlyph(.picked)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.capture.isActive == false else { return }
            self?.setGlyph(.idle)
        }
    }

    // MARK: 단축키 바꾸기

    /// 메뉴의 키 표시를 누르면: 지금 단축키를 잠시 풀고 다음 키 조합을 기다린다
    private func startRecording(in window: NSWindow? = nil) {
        let st = Settings.shared
        guard !st.recording else { return cancelRecording() }
        st.recording = true
        st.shortcutNote = nil
        hotKey.unregister() // 같은 조합을 다시 누를 수 있게
        NSApp.activate(ignoringOtherApps: true)
        (window ?? menuPanel)?.makeKey()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.recorded(e) }
            return nil
        }
    }

    private func recorded(_ e: NSEvent) {
        let st = Settings.shared
        if e.keyCode == 53 && e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            return cancelRecording() // esc
        }
        guard let new = Shortcut(event: e) else {
            st.shortcutNote = L.s.needModifier
            return
        }
        if hotKey.register(new) {
            st.shortcut = new
            st.shortcutNote = nil
            onboarding.model.conflict = false
            Reporting.signal("shortcut.changed")
            endRecording()
        } else {
            st.shortcutNote = L.s.taken(new.text)
            hotKey.unregister()
        }
    }

    private func cancelRecording() {
        onboarding.model.conflict = !hotKey.register(Settings.shared.shortcut)
        Settings.shared.shortcutNote = nil
        endRecording()
    }

    private func endRecording() {
        Settings.shared.recording = false
        if let m = recordMonitor { NSEvent.removeMonitor(m) }
        recordMonitor = nil
    }

    // MARK: 메뉴 (먹색 둥근 창)

    @objc private func toggleMenu() {
        if menuPanel?.isVisible == true { closeMenu() } else { showMenu() }
    }

    private func showMenu() {
        guard let button = statusItem.button, let bw = button.window else { return }
        if menuPanel == nil {
            let p = ToastPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: MenuView(settings: .shared, state: menuState, actions: .init(
                capture: { [weak self] in self?.startCapture() },
                record: { [weak self] in self?.startRecording() },
                about: { [weak self] in self?.about() },
                quit: { NSApp.terminate(nil) },
                relayout: { [weak self] in self?.layoutMenu() })))
            menuPanel = p
        }
        menuState.page = .main
        layoutMenu()
        // 활성 앱이 아니면 SwiftUI가 마우스 올림을 못 받는다 → 잠깐 앞으로, 닫을 때 돌려준다
        let front = NSWorkspace.shared.frontmostApplication
        appBeforeMenu = front?.processIdentifier == getpid() ? appBeforeMenu : front
        NSApp.activate(ignoringOtherApps: true)
        menuPanel?.makeKeyAndOrderFront(nil)
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, Settings.shared.recording == false else { return e } // esc로 닫기
            MainActor.assumeIsolated { self?.closeMenu() }
            return nil
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeMenu() }
        }
    }

    /// 메뉴 크기를 내용에 맞추고 메뉴 막대 아이콘 바로 아래(위쪽 고정)에 둔다
    private func layoutMenu() {
        guard let button = statusItem.button, let bw = button.window, let p = menuPanel, let content = p.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen ?? NSScreen.main!
        var x = b.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - size.width - 4)
        p.setFrame(NSRect(x: x, y: b.minY - size.height + 14, width: size.width, height: size.height), display: true)
    }

    private func closeMenu(restoreFocus: Bool = true) {
        if Settings.shared.recording { cancelRecording() }
        let wasOpen = menuPanel?.isVisible == true
        menuPanel?.orderOut(nil)
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        if let m = menuKeyMonitor { NSEvent.removeMonitor(m) }
        menuKeyMonitor = nil
        if wasOpen, restoreFocus, NSApp.isActive { appBeforeMenu?.activate() }
        appBeforeMenu = nil
    }

    private func about() {
        closeMenu()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L.s.aboutTitle
        a.informativeText = L.s.aboutBody
        a.icon = NSApp.applicationIconImage
        a.runModal()
    }
}

struct MenuView: View {
    struct Actions {
        var capture: () -> Void
        var record: () -> Void
        var about: () -> Void
        var quit: () -> Void
        var relayout: () -> Void = {}
    }

    @ObservedObject var settings: Settings
    @ObservedObject var state: MenuState
    let actions: Actions
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var hoverLang = false
    /// "글자 줍기" 줄에 마우스가 있으면 오른쪽 키 표시가 "바꾸기"로
    @State private var pickHover = false

    var body: some View {
        Group {
            switch state.page {
            case .language:
                LanguagePage(settings: settings, back: { state.page = .main }, openUILanguages: { state.page = .uiLanguage })
            case .uiLanguage:
                UILanguagePage(settings: settings) { state.page = .language }
            case .main:
                mainPage
            }
        }
        .padding(6)
        .frame(width: state.page == .main ? mainWidth : 232)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.inkPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.inkBorder))
        .shadow(color: .black.opacity(0.26), radius: 14, y: 8)
        .padding(18)
        .environment(\.layoutDirection, settings.language.isRTL ? .rightToLeft : .leftToRight)
        .onChange(of: state.page) { _, _ in DispatchQueue.main.async { actions.relayout() } }
        .onChange(of: settings.ocrManual) { _, _ in DispatchQueue.main.async { actions.relayout() } }
        .onChange(of: settings.language) { _, _ in DispatchQueue.main.async { actions.relayout() } }
        .onChange(of: settings.fastMode) { _, _ in DispatchQueue.main.async { actions.relayout() } }
    }

    /// 가장 긴 줄에 맞춘 메뉴 폭(220~320). 바깥 여백 6 포함
    private var mainWidth: CGFloat {
        let t = L.s
        let caps = CGFloat(settings.shortcut.caps.count) * 20
        let lang = settings.language == .auto ? "\(t.auto) · \(Lang.auto.endonym)" : settings.language.endonym
        let rows: [CGFloat] = [
            textWidth(t.pick, 13, .medium) + 16 + caps + 16,
            textWidth(t.openAtLogin, 12.5) + 8 + 36 + 18,
            textWidth(t.joinLines, 12.5) + 8 + 36 + 18,
            textWidth(t.tables, 12.5) + 8 + 36 + 18,
            textWidth(t.reports, 12.5) + 8 + 36 + 18,
            textWidth(t.language, 12.5) + 16 + textWidth(lang, 11) + 22,
            textWidth(t.ocrMode, 12.5) + 14 + textWidth(t.modeFast, 11, .semibold) + textWidth(t.modeAccurate, 11, .semibold) + 34 + 10,
            textWidth(t.about, 12.5) + 24,
            textWidth(t.quit, 12.5) + 50,
            18 + 8 + textWidth(t.appName, 17) + 16 + textWidth(t.tagline, 11) + 28, // 이름 + 태그라인이 다 보이게
        ]
        return min(320, max(220, (rows.max() ?? 0) + 12))
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                AppMarkView(size: 18)
                Text(L.s.appName).font(Fonts.face(15)).tracking(Fonts.faceTracking(15)).foregroundStyle(Color.inkText)
                Spacer()
                Text(L.s.tagline).font(Fonts.font(11)).foregroundStyle(Color.inkFaint)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)

            HStack(spacing: 0) {
                Button(action: actions.capture) {
                    Text(L.s.pick).font(Fonts.font(13, .medium)).foregroundStyle(Color.inkText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ShortcutButton(settings: settings, rowHover: pickHover, action: actions.record)
            }
            .onHover { pickHover = $0 }
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.inkFill))
            if let note = settings.shortcutNote {
                Text(note).font(Fonts.font(11)).foregroundStyle(Color.seal)
                    .padding(.horizontal, 8).padding(.top, 3)
            } else if settings.recording {
                Text(L.s.recordHint).font(Fonts.font(11)).foregroundStyle(Color.inkFaint)
                    .padding(.horizontal, 8).padding(.top, 3)
            }

            rule
            toggle(L.s.openAtLogin, isOn: Binding(get: { login }, set: { on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                login = SMAppService.mainApp.status == .enabled
            }))
            toggle(L.s.joinLines, isOn: $settings.joinLines)
            toggle(L.s.tables, isOn: $settings.tables)
                .opacity(settings.fastMode ? 0.45 : 1)
                .disabled(settings.fastMode)
            modeRow
            if settings.fastMode {
                Text(L.s.modeFastNote).font(.system(size: 10.5)).foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.bottom, 4)
            }
            languageRow
            toggle(L.s.reports, isOn: $settings.reports)
            rule
            MenuRow(title: L.s.about, action: actions.about)
            MenuRow(title: L.s.quit, trailing: "⌘Q", action: actions.quit)
        }
    }

    /// 인식 모드: [빠르게|정확하게] 두 칸
    private var modeRow: some View {
        HStack(spacing: 6) {
            Text(L.s.ocrMode).font(Fonts.font(12.5)).foregroundStyle(Color.inkSub).lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 1) {
                ModeChip(title: L.s.modeFast, selected: settings.fastMode) {
                    settings.fastMode = true
                    LiveText.warmUp()
                }
                ModeChip(title: L.s.modeAccurate, selected: !settings.fastMode) { settings.fastMode = false }
            }
            .padding(1)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.inkFaint.opacity(0.35)))
        }
        .padding(.leading, 8).padding(.trailing, 6).frame(height: 28)
    }

    /// 언어 한 줄: 지금 상태(자동이면 실제 언어)를 보여 주고, 누르면 언어 화면으로
    private var languageRow: some View {
        Button { state.page = .language } label: {
            HStack(spacing: 6) {
                Text(L.s.language).font(Fonts.font(12.5)).foregroundStyle(Color.inkSub)
                Spacer()
                Text(settings.language == .auto ? "\(L.s.auto) · \(Lang.auto.endonym)" : settings.language.endonym)
                    .font(Fonts.font(11)).foregroundStyle(Color.inkFaint).lineLimit(1)
                Image(systemName: "chevron.forward").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(hoverLang ? Color.inkFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverLang = $0 }
    }

    private var rule: some View {
        Rectangle().fill(Color.inkRule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Fonts.font(12.5)).foregroundStyle(Color.inkSub)
                .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            SealCheck(isOn: isOn, label: title)
        }
        .padding(.horizontal, 8).frame(height: 28)
    }
}

/// 디자인의 체크 상자: 꺼지면 옅은 틀, 켜지면 주홍 낙관에 흰 체크
struct SealCheck: View {
    @Binding var isOn: Bool
    let label: String
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(isOn ? Color.seal : .clear)
                RoundedRectangle(cornerRadius: 3).strokeBorder(isOn ? Color.seal : Color.inkFaint, lineWidth: 1.2)
                if isOn {
                    Path { p in p.move(to: CGPoint(x: 3.2, y: 6.9)); p.addLine(to: CGPoint(x: 5.7, y: 9.3)); p.addLine(to: CGPoint(x: 10.1, y: 4.1)) }
                        .stroke(Color(nsColor: Ink.hanjiLight), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: 13, height: 13)
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: 36, height: 28, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L.s.on : L.s.off)
    }
}

/// 메뉴의 키 표시. 누르면 새 단축키를 기다리고(주홍 테두리), 마우스를 올리면 '바꾸기'
struct ShortcutButton: View {
    @ObservedObject var settings: Settings
    var rowHover = false
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Group {
                if settings.recording {
                    Text(L.s.pressKeys).font(Fonts.font(11, .medium)).foregroundStyle(Color.seal)
                        .padding(.horizontal, 6).frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.seal, lineWidth: 1))
                } else if over || rowHover {
                    // 줄에만 올리면 옅게, "바꾸기" 위에 올리면 진하게(누를 수 있다는 표시)
                    Text(L.s.change).font(Fonts.font(11, over ? .medium : .regular)).foregroundStyle(over ? Color.inkText : Color.inkSub)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill(over ? Color.inkFill : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(over ? Color.inkSub.opacity(0.6) : Color.inkFaint.opacity(0.5)))
                } else {
                    HStack(spacing: 3) { ForEach(Array(settings.shortcut.caps.enumerated()), id: \.offset) { KeyCap($0.element) } }
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .help(L.s.changeShortcut)
        .accessibilityLabel("\(L.s.changeShortcut) \(settings.shortcut.text)")
    }
}

struct ModeChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color(nsColor: Ink.hanjiLight) : Color.inkSub)
                .padding(.horizontal, 7).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.seal : (over ? Color.inkFill : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(.system(size: 10)).foregroundStyle(Color.inkSub)
            .padding(.horizontal, 4).frame(height: 16)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.inkFaint.opacity(0.5)))
    }
}

struct MenuRow: View {
    let title: String
    var trailing: String?
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Fonts.font(12.5))
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11)) }
            }
            .foregroundStyle(over ? Color.inkText : Color.inkFaint)
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(over ? Color.inkFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
    }
}

/// 디자인 확인용: 메뉴·알림을 밝게/어둡게 PNG로 그린다. `Jupjup -snapshot <폴더>`
@MainActor
enum Snapshot {
    static func render(to dir: String) {
        let sample = Recognizer.recognize(sampleImage())
        let toast = ToastModel()
        toast.result = sample
        toast.asTable = sample.table != nil
        let actions = ToastView.Actions(toggleTable: {}, toggleJoin: {}, edit: {}, commitEdit: {}, cancelEdit: {}, undo: {})
        let text = Recognized(lines: [[Piece(rect: .zero, text: "최소제곱법은 잔차의 제곱합을 최소로 만드는 계수를 찾는 방법이다.")],
                                      [Piece(rect: .zero, text: "이때 오차항은 서로 독립이며 평균이 0, 분산이 일정하다고 가정한다.")]], table: nil)
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            NSApp.appearance = appearance
            appearance.performAsCurrentDrawingAppearance {
                save(MenuView(settings: .shared, state: MenuState(), actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/menu-\(name).png")
                toast.kind = .picked; toast.hovering = false
                save(ToastView(model: toast, actions: actions), "\(dir)/toast-table-\(name).png")
                toast.hovering = true
                save(ToastView(model: toast, actions: actions), "\(dir)/toast-table-hover-\(name).png")
                let t2 = ToastModel(); t2.result = text; t2.kind = .picked
                save(ToastView(model: t2, actions: actions), "\(dir)/toast-text-\(name).png")
                t2.kind = .working
                save(ToastView(model: t2, actions: actions), "\(dir)/toast-working-\(name).png")
                t2.busyCPU = 94
                save(ToastView(model: t2, actions: actions), "\(dir)/toast-busy-\(name).png")
                t2.busyCPU = nil
                t2.kind = .empty
                save(ToastView(model: t2, actions: actions), "\(dir)/toast-empty-\(name).png")
            }
        }
        for lang in (CommandLine.arguments.contains("-all") ? Lang.concrete : ["en", "ja", "zh-Hans", "ar", "ru", "de"].map(Lang.init(rawValue:))) {
            Settings.shared.language = lang
            NSApp.appearance = NSAppearance(named: .darkAqua)
            save(MenuView(settings: .shared, state: MenuState(), actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/menu-\(lang.rawValue).png")
            let t3 = ToastModel(); t3.result = text; t3.kind = .picked; t3.hovering = true
            save(ToastView(model: t3, actions: actions), "\(dir)/toast-\(lang.rawValue).png")
            t3.kind = .working; t3.busyCPU = 94
            save(ToastView(model: t3, actions: actions), "\(dir)/busy-\(lang.rawValue).png")
        }
        Settings.shared.language = .auto
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let up = MenuState(); up.page = .uiLanguage
        save(MenuView(settings: .shared, state: up, actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/lang-list.png")
        // 고르기 화면 안내줄(정확하게 / 빠르게). 사용자의 설정은 끝나고 되돌린다
        for (name, conflict, perm) in [("first", false, false), ("conflict", true, false), ("done", false, true)] {
            let m = OnboardingModel(); m.conflict = conflict; m.permission = perm
            let v = OnboardingView(model: m, settings: .shared, actions: .init(changeShortcut: {}, openSettings: {}, relaunch: {}, later: {}, try: {}))
            save(v, "\(dir)/onboard-\(name).png")
        }
        let keepFast = Settings.shared.fastMode
        for fast in [false, true] {
            Settings.shared.fastMode = fast
            let ov = OverlayView(frame: NSRect(x: 0, y: 0, width: 1000, height: 120))
            ov.lastRect = CGRect(x: 0, y: 0, width: 10, height: 10)
            if let rep = ov.bitmapImageRepForCachingDisplay(in: ov.bounds) {
                ov.cacheDisplay(in: ov.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/hint-\(fast ? "fast" : "accurate").png"))
            }
        }
        Settings.shared.fastMode = true
        save(MenuView(settings: .shared, state: MenuState(), actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/menu-fast.png")
        Settings.shared.fastMode = keepFast
        let lp = MenuState(); lp.page = .language
        save(MenuView(settings: .shared, state: lp, actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/lang-auto.png")
        let st = Settings.shared, keep = (st.ocrManual, st.ocrLanguages)
        st.ocrManual = true; st.ocrLanguages = ["ko-KR", "en-US", "ja-JP"]
        save(MenuView(settings: .shared, state: lp, actions: .init(capture: {}, record: {}, about: {}, quit: {})), "\(dir)/lang-manual.png")
        (st.ocrManual, st.ocrLanguages) = keep
        print(sample.table?.tsv ?? sample.text)
    }

    private static func save<V: View>(_ view: V, _ path: String) {
        let dark = NSApp.appearance?.name == .darkAqua
        let r = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
        r.scale = 2
        guard let cg = r.cgImage else { return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func sampleImage() -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 360, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 500, height: 180)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 500, height: 180).fill()
        let rows = [["이름", "학과", "학년", "점수"], ["김민지", "컴퓨터공학과", "3", "92.5"], ["Lee Jun", "경영학과", "2", "88"], ["박서연", "전기정보공학부", "4", "100"]]
        for (i, row) in rows.enumerated() {
            for (j, c) in row.enumerated() {
                (c as NSString).draw(at: NSPoint(x: [20, 150, 320, 400][j], y: 140 - CGFloat(i) * 36), withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
