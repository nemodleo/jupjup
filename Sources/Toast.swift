import AppKit
import SwiftUI

// 주워 담음 알림. 오른쪽 위에 2초. 마우스를 올리면 머물고 버튼이 나온다.

/// 줍기 전 클립보드를 통째로 기억했다가 되돌린다.
struct ClipboardBackup {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pb: NSPasteboard = .general) {
        items = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    func restore(_ pb: NSPasteboard = .general) {
        pb.clearContents()
        let objs = items.map { d -> NSPasteboardItem in
            let it = NSPasteboardItem()
            for (t, v) in d { it.setData(v, forType: t) }
            return it
        }
        if !objs.isEmpty { pb.writeObjects(objs) }
    }
}

@MainActor
final class ToastModel: ObservableObject {
    enum Kind { case working, picked, empty, permission, undone }

    @Published var kind: Kind = .picked
    /// 알림이 새로 뜰 때마다 바뀜 → 낙관 찍기 애니메이션을 다시 돌린다
    @Published var stampID = UUID()
    /// 줍는 중일 때 맥이 바쁘면 CPU 사용률(%)
    @Published var busyCPU: Int?
    @Published var result = Recognized(lines: [], table: nil)
    @Published var asTable = false
    @Published var joined = false
    @Published var hovering = false
    @Published var editing = false
    @Published var draft = ""
    /// 고쳐서 담았으면 그 글이 우선
    @Published var edited: String?

    var backup: ClipboardBackup?

    var copiedText: String {
        if let edited { return edited }
        if asTable, let t = result.table { return t.tsv }
        return joined ? result.joinedText : result.text
    }

    var meta: String {
        let t = L.s
        if edited != nil { return t.editedMeta(copiedText.count) }
        if asTable, let tb = result.table { return t.tableMeta(tb.rows.count, tb.columnCount) }
        return t.textMeta(joined ? 1 : result.lines.count, copiedText.count)
    }

    var preview: String {
        if asTable, edited == nil, let t = result.table {
            return t.rows.prefix(3).map { $0.joined(separator: "  ·  ") }.joined(separator: "\n")
        }
        return copiedText
    }

    func writeClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if edited == nil, asTable, let t = result.table {
            pb.setString(t.tsv, forType: .string)
            pb.setString(t.html, forType: .html)
        } else {
            pb.setString(copiedText, forType: .string)
        }
    }
}

final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ToastController {
    let model = ToastModel()
    private var panel: ToastPanel?
    private var hosting: NSHostingView<ToastView>?
    private var poll: Timer?
    private var hideAt: Date?
    private var anchor: NSPoint = .zero

    func show(_ kind: ToastModel.Kind, result: Recognized? = nil, backup: ClipboardBackup? = nil, busyCPU: Int? = nil) {
        let m = model
        if kind != m.kind || kind == .picked { m.stampID = UUID() }
        m.kind = kind
        m.busyCPU = kind == .working ? busyCPU : nil
        m.editing = false
        m.edited = nil
        m.hovering = false
        if let result {
            m.result = result
            m.asTable = Settings.shared.tables && result.table != nil
            m.joined = Settings.shared.joinLines
            m.backup = backup
        }
        if kind == .picked { m.writeClipboard() }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        anchor = NSPoint(x: screen.visibleFrame.maxX - 16, y: screen.visibleFrame.maxY - 12)

        if panel == nil { build() }
        layoutNow()
        // 읽는 중 알림이 떠 있으면 그 자리에서 결과로 바꿔 끼운다(깜빡임 없이)
        if panel?.isVisible != true || panel?.alphaValue ?? 0 < 1 {
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel?.animator().alphaValue = 1 }
        }
        panel?.displayIfNeeded()
        switch kind {
        case .working: hideAt = Date().addingTimeInterval(30) // 결과가 오면 바뀜. 혹시 멈추면 30초 뒤 닫음
        case .permission: hideAt = Date().addingTimeInterval(5)
        default: hideAt = Date().addingTimeInterval(2.2)
        }
        startPolling()
    }

    private func build() {
        let p = ToastPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ToastView(model: model, actions: .init(
            toggleTable: { [weak self] in self?.update { $0.asTable.toggle() } },
            toggleJoin: { [weak self] in self?.update { $0.joined.toggle() } },
            edit: { [weak self] in self?.beginEdit() },
            commitEdit: { [weak self] in self?.commitEdit() },
            cancelEdit: { [weak self] in self?.endEdit() },
            undo: { [weak self] in self?.undo() }
        ))
        let h = NSHostingView(rootView: view)
        p.contentView = h
        hosting = h
        panel = p
    }

    private func update(_ f: (ToastModel) -> Void) {
        f(model)
        model.writeClipboard()
        relayout()
    }

    /// 오른쪽 위 꼭짓점을 고정한 채 내용 크기에 맞춘다
    private func relayout() {
        DispatchQueue.main.async { [self] in layoutNow() }
    }

    private func layoutNow() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height), display: true)
    }

    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let panel else { return }
        let inside = NSMouseInRect(NSEvent.mouseLocation, panel.frame.insetBy(dx: -4, dy: -4), false)
        if inside != model.hovering, model.kind == .picked {
            model.hovering = inside
            relayout()
        }
        if inside || model.editing {
            hideAt = Date().addingTimeInterval(1.2)
        } else if let t = hideAt, Date() > t {
            hide()
        }
    }

    func hide() {
        poll?.invalidate()
        poll = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func beginEdit() {
        model.draft = model.copiedText
        model.editing = true
        relayout()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    private func commitEdit() {
        model.edited = model.draft
        model.writeClipboard()
        endEdit()
    }

    private func endEdit() {
        model.editing = false
        panel?.resignKey()
        NSApp.hide(nil) // 이전 앱으로 초점 돌려주기
        relayout()
    }

    private func undo() {
        model.backup?.restore()
        model.kind = .undone
        model.hovering = false
        relayout()
        hideAt = Date().addingTimeInterval(1.2)
    }
}

struct ToastView: View {
    struct Actions {
        var toggleTable: () -> Void
        var toggleJoin: () -> Void
        var edit: () -> Void
        var commitEdit: () -> Void
        var cancelEdit: () -> Void
        var undo: () -> Void
    }

    @ObservedObject var model: ToastModel
    let actions: Actions

    private var expanded: Bool { model.kind == .picked && (model.hovering || model.editing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: model.kind == .picked ? .top : .center, spacing: 10) {
                mark
                VStack(alignment: .leading, spacing: 3) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.kind == .working, let busy = model.busyCPU { busyLine(busy) }
            if model.kind == .picked && model.editing { editor }
            else if model.kind == .picked && model.hovering { buttons }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, expanded ? 8 : 10)
        .frame(width: toastWidth)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.inkPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.inkBorder))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .padding(18) // 그림자 자리
        .environment(\.layoutDirection, Settings.shared.language.isRTL ? .rightToLeft : .leftToRight)
    }

    /// B안: 줍는 중 = 도는 점선 틀, 다 됨 = 도장처럼 찍히는 주홍 ✓ 낙관
    @ViewBuilder private var mark: some View {
        switch model.kind {
        case .working: MarchingFrame()
        case .picked: StampCheck().id(model.stampID)
        default: AppMarkView(state: markState, size: 24)
        }
    }

    /// 기본 300. 마우스를 올려 버튼이 나올 때 버튼 글이 길면(독일어 등) 380까지 넓힌다
    private var toastWidth: CGFloat {
        guard model.kind == .picked, model.hovering, !model.editing else { return 300 }
        let t = L.s
        var labels = [t.edit, t.undo]
        if model.edited == nil {
            if model.result.table != nil { labels.append(model.asTable ? t.asText : t.asTable) }
            if !model.asTable && model.result.lines.count > 1 { labels.append(model.joined ? t.keepLines : t.joinOne) }
        }
        let buttons = labels.reduce(0) { $0 + textWidth($1, 12, .medium) + 16 + 2 }
        return min(380, max(300, buttons + 24 + 8))
    }

    private var markState: AppMark.State {
        switch model.kind {
        case .working: .working
        case .picked: .picked
        default: .empty
        }
    }

    /// 제목 + 옅은 덧말 한 줄
    private func title(_ t: String, _ meta: String, done: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(t).font(Fonts.face(14)).tracking(Fonts.faceTracking(14)).foregroundStyle(done ? Color.sealText : Color.inkText)
            Text(meta).font(Fonts.font(11)).foregroundStyle(Color.inkFaint).lineLimit(1)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.kind {
        case .picked:
            title(L.s.picked, model.meta, done: true)
            if !model.editing, model.asTable, model.edited == nil, let t = model.result.table {
                tablePreview(t)
            } else if !model.editing {
                Text(model.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkSub)
                    .lineSpacing(1)
                    .lineLimit(model.hovering ? 6 : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .working:
            title(L.s.working, L.s.workingSub)
        case .empty:
            title(L.s.empty, L.s.emptySub)
        case .permission:
            title(L.s.permission, "")
            Text(L.s.permissionSub)
                .font(Fonts.font(11)).foregroundStyle(Color.inkFaint).fixedSize(horizontal: false, vertical: true)
        case .undone:
            title(L.s.undone, L.s.undoneSub)
        }
    }

    /// 맥이 바쁠 때: 주홍 ! + 경고 + 지금 CPU 사용률
    private func busyLine(_ percent: Int) -> some View {
        HStack(spacing: 6) {
            Text("!").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(nsColor: Ink.hanjiLight))
                .frame(width: 14, height: 14).background(Circle().fill(Color.seal))
            Text(L.s.busy).font(Fonts.font(11)).foregroundStyle(Color.sealText)
            Spacer()
            Text("CPU \(percent)%").font(.system(size: 11)).foregroundStyle(Color.inkFaint)
        }
        .padding(.top, 7)
        .overlay(alignment: .top) { Rectangle().fill(Color.inkRule).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// 표는 칸을 맞춘 격자로 몇 줄만
    private func tablePreview(_ t: Table) -> some View {
        let rows = Array(t.rows.prefix(model.hovering ? 6 : 3))
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    ForEach(rows[i].indices, id: \.self) { j in
                        Text(rows[i][j]).lineLimit(1)
                            .font(.system(size: 12, weight: i == 0 ? .medium : .regular))
                            .foregroundStyle(i == 0 ? Color.inkText : Color.inkSub)
                    }
                }
            }
            if t.rows.count > rows.count {
                Text(L.s.moreRows(t.rows.count - rows.count)).font(Fonts.font(11)).foregroundStyle(Color.inkFaint)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 2) {
            Spacer()
            if model.edited == nil {
                if model.result.table != nil {
                    ToastButton(title: model.asTable ? L.s.asText : L.s.asTable, action: actions.toggleTable)
                }
                if !model.asTable && model.result.lines.count > 1 {
                    ToastButton(title: model.joined ? L.s.keepLines : L.s.joinOne, action: actions.toggleJoin)
                }
            }
            ToastButton(title: L.s.edit, action: actions.edit)
            ToastButton(title: L.s.undo, strong: true, action: actions.undo)
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Rectangle().fill(Color.inkRule).frame(height: 1) }
    }

    private var editor: some View {
        VStack(spacing: 6) {
            TextEditor(text: $model.draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.inkFill))
            HStack(spacing: 2) {
                Spacer()
                ToastButton(title: L.s.cancel, action: actions.cancelEdit)
                ToastButton(title: L.s.save, strong: true, action: actions.commitEdit)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

/// 고르기 화면의 점선 모서리가 표지 안에서 도는 모습
struct MarchingFrame: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            RoundedRectangle(cornerRadius: 3)
                // 점선 위치는 무늬 한 주기(5+4=9) 안에서만. 시각을 그대로 쓰면 수십억이 되어
                // 점선 계산이 메인 스레드를 수십 초 붙잡는다(실측: 인식 중 화면 멈춤의 원인)
                .strokeBorder(Color.seal, style: StrokeStyle(lineWidth: 2, dash: [5, 4], dashPhase: -CGFloat((t * 22).truncatingRemainder(dividingBy: 9))))
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(L.s.working)
    }
}

/// 꽉 찬 주홍 낙관에 ✓. 나타날 때 도장처럼 크게 → 살짝 눌림 → 제자리
struct StampCheck: View {
    @State private var landed = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color.seal)
            Path { p in
                p.move(to: CGPoint(x: 6.5, y: 12.5)); p.addLine(to: CGPoint(x: 10.3, y: 16.2)); p.addLine(to: CGPoint(x: 17.8, y: 7.8))
            }
            .stroke(Color(nsColor: Ink.hanjiLight), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: 24, height: 24)
        .shadow(color: Color.seal.opacity(landed ? 0.35 : 0), radius: 4, y: 2)
        .scaleEffect(landed ? 1 : 1.6)
        .opacity(landed ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { landed = true }
        }
        .accessibilityLabel(L.s.done)
    }
}

struct ToastButton: View {
    let title: String
    var strong = false
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fonts.font(12, strong ? .medium : .regular))
                .lineLimit(1).fixedSize()
                .foregroundStyle(strong ? Color.inkText : Color.inkSub)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(strong || over ? Color.inkFill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
    }
}
