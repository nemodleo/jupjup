import AppKit
import ScreenCaptureKit

// 고르기 화면. 마우스가 있는 화면을 먼저 통째로 찍어 멈춰 두고, 그 위에서 영역을 고른다.

enum CaptureError: Error { case permission, noDisplay }

@MainActor
final class CaptureController {
    /// 고른 조각과 그 자리(화면 좌표)
    var onPicked: ((CGImage, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((CaptureError) -> Void)?

    private var window: OverlayWindow?
    private var previousApp: NSRunningApplication?
    private var last: (screen: CGDirectDisplayID, rect: CGRect)?
    private var starting = false

    var isActive: Bool { window != nil || starting }

    /// 열리자마자 방금 그 자리를 다시 담을지(알림의 "같은 자리 다시")
    private var pendingLast = false

    /// 방금 그 자리를 다시 찍는다. 기억한 자리가 없으면 그냥 고르기 화면이 열린다
    func repeatLast() {
        if let w = window { w.overlay.useLast(); return }
        pendingLast = last != nil
        start()
    }

    /// returnTo: 다 고르면 앞으로 돌려줄 앱(메뉴에서 시작했을 때 메뉴 전 앱). 없으면 지금 앞에 있는 앱
    func start(returnTo: NSRunningApplication? = nil) {
        if let w = window { w.overlay.useLast(); return } // 고르는 중 단축키 다시 → 방금 그 자리
        guard !starting else { return }
        starting = true
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            starting = false
            onError?(.noDisplay)
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = returnTo ?? (front?.processIdentifier == getpid() ? nil : front)
        Task {
            defer { starting = false }
            do {
                let image = try await Self.snapshot(display: id, screen: screen)
                show(image: image, screen: screen, id: id)
            } catch {
                onError?(.permission)
            }
        }
    }

    private static func snapshot(display id: CGDirectDisplayID, screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = Int(screen.frame.width * screen.backingScaleFactor)
        cfg.height = Int(screen.frame.height * screen.backingScaleFactor)
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// 이 화면 위에 보이는 창들의 테두리(앞→뒤 순서, 오버레이 좌표)
    private static func windowRects(screen: NSScreen, id: CGDirectDisplayID) -> [CGRect] {
        let cg = CGDisplayBounds(id)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != getpid(),
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.width > 40, r.height > 40 else { return nil }
            // CG 전역(왼쪽 위 원점) → 이 화면 안, 왼쪽 아래 원점
            let local = CGRect(x: r.minX - cg.minX, y: cg.height - (r.maxY - cg.minY), width: r.width, height: r.height)
            let clipped = local.intersection(CGRect(origin: .zero, size: screen.frame.size))
            return clipped.isNull || clipped.width < 40 ? nil : clipped
        }
    }

    private func show(image: CGImage, screen: NSScreen, id: CGDirectDisplayID) {
        let w = OverlayWindow(screen: screen)
        let v = w.overlay
        v.image = image
        v.windows = Self.windowRects(screen: screen, id: id)
        v.lastRect = last?.screen == id ? last?.rect : nil
        v.onFinish = { [weak self] rect in self?.finish(rect: rect, id: id) }
        v.onCancel = { [weak self] in self?.close(); self?.onCancel?() }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
        if pendingLast { pendingLast = false; v.useLast() }
    }

    private func finish(rect: CGRect, id: CGDirectDisplayID) {
        guard let v = window?.overlay, let image = v.image else { return }
        last = (id, rect)
        let scale = CGFloat(image.width) / v.bounds.width
        let crop = CGRect(x: rect.minX * scale, y: (v.bounds.height - rect.maxY) * scale,
                          width: rect.width * scale, height: rect.height * scale).integral
        let piece = image.cropping(to: crop)
        let origin = window?.frame.origin ?? .zero
        let onScreen = rect.offsetBy(dx: origin.x, dy: origin.y)
        close()
        if let piece { onPicked?(piece, onScreen) } else { onCancel?() }
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        previousApp?.activate()
        previousApp = nil
    }
}

final class OverlayWindow: NSWindow {
    let overlay: OverlayView

    init(screen: NSScreen) {
        overlay = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = overlay
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    var image: CGImage?
    var windows: [CGRect] = []
    var lastRect: CGRect?
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var windowMode = false
    /// 안내줄의 [빠르게|정확하게] 칩 위치(누르기 판정용)
    private var fastChip: CGRect = .zero, accurateChip: CGRect = .zero
    private var anchor: NSPoint?
    private var selection: CGRect?
    private var hovered: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: windowMode ? .pointingHand : .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    func useLast() {
        if let r = lastRect { onFinish?(r) }
    }

    // MARK: 입력

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        // 안내줄의 인식 모드 칩
        if fastChip.insetBy(dx: -2, dy: -4).contains(p) { setMode(fast: true); return }
        if accurateChip.insetBy(dx: -2, dy: -4).contains(p) { setMode(fast: false); return }
        if windowMode {
            if let w = windows.first(where: { $0.contains(p) }) { onFinish?(w) }
            return
        }
        anchor = p
        selection = nil
    }

    override func mouseDragged(with e: NSEvent) {
        guard let a = anchor else { return }
        let p = convert(e.locationInWindow, from: nil)
        selection = CGRect(x: min(a.x, p.x), y: min(a.y, p.y), width: abs(p.x - a.x), height: abs(p.y - a.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { anchor = nil }
        if let s = selection, s.width >= 6, s.height >= 6 {
            onFinish?(s.integral)
        } else {
            selection = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with e: NSEvent) {
        guard windowMode else { return }
        let p = convert(e.locationInWindow, from: nil)
        let h = windows.first(where: { $0.contains(p) })
        if h != hovered { hovered = h; needsDisplay = true }
    }

    override func keyDown(with e: NSEvent) {
        switch Int(e.keyCode) {
        case 53: onCancel?() // esc
        case 48: setMode(fast: !MainActor.assumeIsolated { Settings.shared.fastMode }) // 탭: 모드 바꾸기
        case 18 where e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty: setMode(fast: true)  // 1: 빠르게
        case 19 where e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty: setMode(fast: false) // 2: 정확하게
        case 49: // 스페이스: 창 통째로 ↔ 끌어서
            windowMode.toggle()
            selection = nil
            anchor = nil
            hovered = windowMode ? windows.first(where: { $0.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)) }) : nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        case 36, 76: if let s = selection { onFinish?(s.integral) } // 리턴
        default: break
        }
    }

    // MARK: 그리기

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let image { ctx.draw(image, in: bounds) }

        let lit = windowMode ? hovered : selection
        let dim = NSBezierPath(rect: bounds)
        if let lit { dim.append(NSBezierPath(rect: lit)) }
        dim.windingRule = .evenOdd
        Ink.mook.withAlphaComponent(0.42).setFill()
        dim.fill()

        if let lit {
            drawBrackets(around: lit)
            chip("\(Int(lit.width)) × \(Int(lit.height))", below: lit)
        }
        hintBar()
    }

    private func drawBrackets(around r: CGRect) {
        let o = r.insetBy(dx: -6, dy: -6)
        let len = min(24, o.width / 3, o.height / 3)
        let p = NSBezierPath()
        p.lineWidth = 3
        p.lineCapStyle = .square
        for (c, dx, dy) in [(NSPoint(x: o.minX, y: o.minY), 1.0, 1.0), (NSPoint(x: o.maxX, y: o.minY), -1.0, 1.0),
                            (NSPoint(x: o.maxX, y: o.maxY), -1.0, -1.0), (NSPoint(x: o.minX, y: o.maxY), 1.0, -1.0)] {
            p.move(to: NSPoint(x: c.x, y: c.y + dy * len))
            p.line(to: c)
            p.line(to: NSPoint(x: c.x + dx * len, y: c.y))
        }
        Ink.seal.setStroke()
        p.stroke()
    }

    private func chip(_ text: String, below r: CGRect) {
        let s = NSAttributedString(string: text, attributes: [.font: Fonts.nsFont(11, .medium), .foregroundColor: Ink.hanji, .kern: 0.4])
        let size = s.size()
        var box = CGRect(x: r.minX, y: r.minY - 12 - size.height - 6, width: size.width + 16, height: size.height + 6)
        if box.minY < 8 { box.origin.y = r.minY + 8 } // 화면 아래 끝이면 안쪽으로
        Ink.mook.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        s.draw(at: NSPoint(x: box.minX + 8, y: box.minY + 3))
    }

    private func hintBar() {
        let (t, shortcut) = MainActor.assumeIsolated { (L.s, Settings.shared.shortcut.text) }
        let items: [(String, Bool)] = windowMode
            ? [(t.pickWindow, true), (t.spaceDrag, false), (t.escCancel, false)]
            : [(t.dragSelect, true), (t.spaceWindow, false)]
              + (lastRect != nil ? [(t.sameSpot(shortcut), false)] : []) + [(t.escCancel, false)]
        let strs = items.map { t, strong in
            NSAttributedString(string: t, attributes: [.font: Fonts.nsFont(12, strong ? .semibold : .regular),
                                                       .foregroundColor: strong ? Ink.hanji : NSColor(hex: 0x9C9488),
                                                       .kern: strong ? 0.5 : 0])
        }
        let fast = MainActor.assumeIsolated { Settings.shared.fastMode }
        /// "1 빠르게"처럼 칩 앞에 작은 숫자 = 누를 키
        func chipText(_ key: String, _ str: String, _ on: Bool) -> NSAttributedString {
            let color = on ? Ink.hanjiLight : NSColor(hex: 0xCFC7B9)
            let a = NSMutableAttributedString(string: key + " ", attributes: [.font: Fonts.nsFont(9.5), .foregroundColor: color.withAlphaComponent(on ? 0.8 : 0.6)])
            a.append(NSAttributedString(string: str, attributes: [.font: Fonts.nsFont(11, on ? .semibold : .regular), .foregroundColor: color]))
            return a
        }
        let fastStr = chipText("1", t.modeFast, fast), accStr = chipText("2", t.modeAccurate, !fast)
        let chipW = { (a: NSAttributedString) in a.size().width + 14 }
        let segW = chipW(fastStr) + chipW(accStr) + 3
        let gap: CGFloat = 14, mark: CGFloat = 18
        let width = strs.reduce(0) { $0 + $1.size().width } + gap * CGFloat(strs.count - 1) + 8 + mark + 8 + 12
            + gap + 1 + gap + segW
        let height: CGFloat = 32
        let box = CGRect(x: bounds.midX - width / 2, y: 32, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.set()
        Ink.mook.setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        if let ctx = NSGraphicsContext.current?.cgContext {
            AppMark.draw(in: ctx, rect: CGRect(x: box.minX + 8, y: box.midY - mark / 2, width: mark, height: mark), state: .picked)
        }
        var x = box.minX + 8 + mark + 8
        for s in strs {
            s.draw(at: NSPoint(x: x, y: box.midY - s.size().height / 2))
            x += s.size().width + gap
        }
        // 구분선 + [1 빠르게|2 정확하게] (메뉴의 모드 설정과 같은 값)
        NSColor(hex: 0xE4DDCF, alpha: 0.15).setFill()
        NSRect(x: x, y: box.midY - 8, width: 1, height: 16).fill()
        x += 1 + gap
        let seg = CGRect(x: x, y: box.midY - 11, width: segW, height: 22)
        NSColor(hex: 0xE4DDCF, alpha: 0.18).setStroke()
        let outline = NSBezierPath(roundedRect: seg.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        outline.lineWidth = 1
        outline.stroke()
        fastChip = CGRect(x: seg.minX + 1.5, y: seg.minY + 2, width: chipW(fastStr), height: 18)
        accurateChip = CGRect(x: fastChip.maxX, y: seg.minY + 2, width: chipW(accStr), height: 18)
        Ink.seal.setFill()
        NSBezierPath(roundedRect: fast ? fastChip : accurateChip, xRadius: 4, yRadius: 4).fill()
        for (str, r) in [(fastStr, fastChip), (accStr, accurateChip)] {
            str.draw(at: NSPoint(x: r.midX - str.size().width / 2, y: r.midY - str.size().height / 2))
        }
    }

    /// 이번 캡쳐부터 쓸 인식 모드를 바꾼다(메뉴 설정과 같은 값이라 저장됨)
    private func setMode(fast: Bool) {
        MainActor.assumeIsolated {
            guard Settings.shared.fastMode != fast else { return }
            Settings.shared.fastMode = fast
            if fast { LiveText.warmUp() }
        }
        needsDisplay = true
    }
}
