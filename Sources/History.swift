import SwiftUI

// 복사 기록. 주운 글을 최근 20개까지 이 맥에만 둔다(~/Library/Application Support/Jupjup/history.json, 나만 읽기).
// 어디로도 보내지 않는다. 메뉴 "기록"에서 다시 누르면 그때 담았던 모양(한 줄·표·고친 글) 그대로 클립보드에.
// 알림에서 모양을 바꾸면 같은 기록이 고쳐지고, 되돌리기를 누르면 그 기록은 지운다.

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    /// 인식한 줄(원문). 다시 담을 때 한 줄·표 바꾸기를 그대로 쓸 수 있게
    var lines: [String]
    var table: [[String]]?
    var codes: [CodePayload]
    var joined: Bool
    var asTable: Bool
    var edited: String?

    struct CodePayload: Codable, Equatable { var payload: String; var isQR: Bool }

    var recognized: Recognized {
        Recognized(lines: lines.map { [Piece(rect: .zero, text: $0)] }, table: table.map(Table.init(rows:)),
                   codes: codes.map { Code(rect: .zero, payload: $0.payload, isQR: $0.isQR) })
    }

    /// 담았던 글 그대로
    var copied: String {
        if let edited { return edited }
        let r = recognized
        if asTable, let t = r.table { return t.tsv }
        return joined ? r.joinedText : r.text
    }

    /// 목록에 보일 한 줄
    var title: String {
        let s = (asTable ? table?.first?.joined(separator: " · ") : nil) ?? copied
        return s.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// 덧말: 표면 "표", QR이면 "QR", 아니면 없음
    @MainActor var tag: String? {
        let t = L.s
        if edited == nil, asTable, table != nil { return t.historyTable }
        if !codes.isEmpty { return codes.contains { $0.isQR } ? t.qr : t.barcode }
        return nil
    }
}

@MainActor
final class History: ObservableObject {
    static let shared = History()
    static let limit = 20

    @Published private(set) var entries: [HistoryEntry] = []

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Jupjup")
        return dir.appendingPathComponent("history.json")
    }()

    /// 스냅샷용: 디스크에 안 쓰는 기록
    private var persist = true
    init(preview: [HistoryEntry]) { entries = preview; persist = false }

    private init() {
        guard Settings.shared.history, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = Array(saved.prefix(Self.limit))
    }

    /// 알림이 클립보드에 쓸 때마다: 같은 id면 고치고 맨 위로, 없으면 새로
    func put(_ id: UUID, model m: ToastModel) {
        guard Settings.shared.history, !m.copiedText.isEmpty else { return }
        let r = m.result
        let e = HistoryEntry(id: id, date: entries.first { $0.id == id }?.date ?? Date(),
                             lines: r.lines.map { $0.map(\.text).joined(separator: " ") }, table: r.table?.rows,
                             codes: r.codes.map { .init(payload: $0.payload, isQR: $0.isQR) },
                             joined: m.joined, asTable: m.asTable, edited: m.edited)
        entries.removeAll { $0.id == id || $0.copied == e.copied } // 같은 글은 하나만
        entries.insert(e, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        if persist { try? FileManager.default.removeItem(at: file) }
    }

    private func save() {
        guard persist else { return }
        guard !entries.isEmpty else { return clear() }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

extension History {
    /// `Jupjup -historytest`: 디스크에 안 쓰는 기록으로 고치기·같은 글 하나만·20개 제한·되돌리기·저장 모양을 본다
    static func selfTest() -> Bool {
        let h = History(preview: []), m = ToastModel()
        var ok = true
        func check(_ c: Bool, _ what: String) { print((c ? "통과 " : "실패 ") + what); ok = ok && c }
        let lines = ["Deep resid-", "ual learning", "a | b"]
        m.result = Recognized(lines: lines.map { [Piece(rect: .zero, text: $0)] }, table: Table(rows: [["a", "b"], ["1", "2"]]))
        let id = UUID()
        h.put(id, model: m)
        check(h.entries.count == 1 && h.entries[0].copied == m.copiedText, "새 기록")
        m.joined = true; h.put(id, model: m)
        check(h.entries.count == 1 && h.entries[0].copied == "Deep residual learning a | b", "한 줄로 바꾸면 같은 기록이 고쳐짐")
        m.asTable = true; h.put(id, model: m)
        check(h.entries[0].copied == "a\tb\n1\t2" && h.entries[0].title == "a · b", "표로 바꾸면 TSV, 목록엔 첫 행")
        let copy = ToastModel(); copy.result = m.result; copy.joined = true; copy.asTable = true
        h.put(UUID(), model: copy)
        check(h.entries.count == 1, "같은 글은 하나만")
        for i in 0..<25 { let x = ToastModel(); x.result = Recognized(lines: [[Piece(rect: .zero, text: "글 \(i)")]], table: nil); h.put(UUID(), model: x) }
        check(h.entries.count == limit && h.entries[0].copied == "글 24", "20개까지, 최근 것이 위")
        let top = h.entries[0].id; h.remove(top)
        check(!h.entries.contains { $0.id == top }, "되돌리면 지움")
        let e = HistoryEntry(id: UUID(), date: Date(), lines: lines, table: [["a", "b"]], codes: [.init(payload: "https://x.y", isQR: true)],
                             joined: false, asTable: false, edited: "고친 글")
        let back = (try? JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(e)))
        check(back == e && back?.copied == "고친 글" && back?.recognized.codes.first?.isQR == true, "저장했다 읽어도 같음")
        return ok
    }
}

/// 메뉴의 기록 화면: 최근 것이 위. 누르면 그 글을 다시 담고 알림을 띄운다
struct HistoryPage: View {
    @ObservedObject var settings: Settings
    @ObservedObject var history: History
    let back: () -> Void
    let pick: (HistoryEntry) -> Void

    var body: some View {
        let t = L.s
        VStack(alignment: .leading, spacing: 1) {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.backward").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.inkSub)
                    Text(t.history).font(Fonts.font(13, .semibold)).foregroundStyle(Color.inkText)
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.back)

            if history.entries.isEmpty {
                Text(settings.history ? t.historyEmpty : t.historyOff)
                    .font(Fonts.font(12)).foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 22)
            } else {
                let list = VStack(alignment: .leading, spacing: 0) {
                    ForEach(history.entries) { e in HistoryRow(entry: e) { pick(e) } }
                }
                // 여덟 개까지는 그대로, 넘으면 그 높이에서 굴린다
                if history.entries.count <= 8 { list } else { ScrollView(.vertical) { list }.frame(height: 42 * 8) }
            }

            Rectangle().fill(Color.inkRule).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            HStack {
                Text(t.historyKeep).font(Fonts.font(12.5)).foregroundStyle(Color.inkSub).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                SealCheck(isOn: $settings.history, label: t.historyKeep)
            }
            .padding(.horizontal, 8).frame(height: 28)
            Text(t.historyNote).font(.system(size: 11)).foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.bottom, 2)
            if !history.entries.isEmpty {
                MenuRow(title: t.historyClear) {
                    Reporting.signal("history.cleared")
                    history.clear()
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(Fonts.font(12.5)).foregroundStyle(over ? Color.inkText : Color.inkSub)
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 4) {
                    if let tag = entry.tag { Text(tag); Text("·") }
                    Text(Self.ago(entry.date))
                }
                .font(.system(size: 10.5)).foregroundStyle(Color.inkFaint).lineLimit(1)
            }
            .padding(.horizontal, 8).frame(height: 42, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(over ? Color.inkFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .help(String(entry.copied.prefix(400)))
    }

    /// "3분 전" — 화면 언어로
    @MainActor static func ago(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named // 1분 안이면 "지금"
        f.locale = Locale(identifier: Settings.shared.language.resolved.rawValue)
        let now = Date()
        return f.localizedString(for: now.timeIntervalSince(d) < 60 ? now : d, relativeTo: now)
    }
}
