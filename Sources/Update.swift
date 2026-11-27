import AppKit
import UserNotifications

/// 새 버전 알림. 소개 사이트의 version.json을 켤 때와 하루에 한 번 본다.
/// 보내는 건 쿠키·식별자 없는 GET 하나. 메뉴의 "새 버전 확인"을 끄면 아예 안 본다.
/// 자동 설치는 하지 않는다(공증 전이라). 새 버전이 있으면 메뉴 맨 위에 "새 버전 1.1 · 내려받기"가 뜬다.
/// 버전마다 한 번 macOS 알림도 띄운다(updateNotified에 적어 둠). 권한은 그때 처음 묻고, 고르기 화면·토스트가 떠 있으면 미룬다
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Feed: Decodable { let version: String; let url: String; let min_os: String? }

    /// 시험할 때는 `defaults write com.nemo.jupjup updateURL file:///…/version.json`
    var feed: URL {
        UserDefaults.standard.string(forKey: "updateURL").flatMap(URL.init(string:)) ?? URL(string: "https://jupjup.d-t-it.com/version.json")!
    }
    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    /// 고르기 화면이나 토스트가 떠 있는지. 앱이 채운다
    var isBusy: () -> Bool = { false }
    /// 진단(-checkupdate)처럼 알림을 띄우면 안 될 때 끈다
    var notify = true

    /// macOS가 낮아 못 쓰는 버전일 때 여는 곳: 시스템 설정 › 소프트웨어 업데이트
    static let softwareUpdate = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!

    private var timer: Timer?
    /// 띄우기를 기다리는 알림과, 1초마다 바쁜지 보는 시계
    private var pending: UpdateInfo?
    private var wait: Timer?
    private var lastBusy: Date?
    private let notices = UpdateNotices()
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral // 쿠키·캐시 없음
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    /// 번들 없이 돌면(swift run 등) 알림 센터를 건드리지 않는다
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        if canNotify { UNUserNotificationCenter.current().delegate = notices } // 눌렀을 때·앱이 앞일 때를 받으려고 뜰 때 건다
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        guard Settings.shared.updateCheck else { return }
        let url = feed, mine = current
        Task {
            guard let (data, resp) = try? await Self.session.data(from: url) else { return }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { return }
            guard let f = try? JSONDecoder().decode(Feed.self, from: data), let link = URL(string: f.url),
                  Self.trusted(link) else { return }
            let newer = isNewer(f.version, than: mine)
            if newer, Settings.shared.update?.version != f.version { Reporting.signal("update.available", ["version": f.version]) }
            let info = UpdateInfo(version: f.version, url: link, minOS: f.min_os, runsHere: runs(minOS: f.min_os, on: Self.thisOS))
            Settings.shared.update = newer ? info : nil
            if newer { arm(info) }
        }
    }

    /// 아직 안 알린 버전이면 기다리게 둔다. 1초마다 보고, 하던 일이 끝나고 5초 지난 첫 틱에 한 번 띄운다
    private func arm(_ info: UpdateInfo) {
        guard notify, canNotify, shouldNotify(version: info.version, notified: UserDefaults.standard.string(forKey: "updateNotified"),
                                      checkOn: Settings.shared.updateCheck) else { return }
        pending = info
        guard wait == nil else { return }
        wait = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        // 새 버전 확인을 끄면 기다리던 알림도 버린다
        guard let info = pending, Settings.shared.updateCheck else { return stopWaiting() }
        let busy = isBusy()
        if busy { lastBusy = Date() }
        guard canFire(now: Date(), lastBusy: lastBusy, busy: busy) else { return }
        stopWaiting()
        Task { await announce(info) }
    }

    private func stopWaiting() {
        wait?.invalidate()
        wait = nil
        pending = nil
    }

    /// 시스템 알림 한 번. 소리·배지 없음. 거절이면 조용히 끝(메뉴 줄은 그대로, 다시 묻지 않게 적어 둔다).
    /// 권한 창은 몇 초 뒤 사라지는 배너라 놓치기 쉽다 — 답하지 않고 넘긴 것(아직 안 정함)이면 적지 않고 다음 확인 때 다시 묻는다
    private func announce(_ info: UpdateInfo) async {
        let key = "updateNotified", center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else {
            if await center.notificationSettings().authorizationStatus == .denied { UserDefaults.standard.set(info.version, forKey: key) }
            return
        }
        let t = L.s, c = UNMutableNotificationContent()
        if info.runsHere {
            c.title = t.updateNoteTitle(info.version); c.body = t.updateNoteBody
        } else {
            c.title = t.updateOSTitle(info.version, osLabel(info.minOS ?? "")); c.body = t.updateOSBody
        }
        c.userInfo = ["version": info.version, "url": info.url.absoluteString, "runsHere": info.runsHere]
        let req = UNNotificationRequest(identifier: "update-\(info.version)", content: c, trigger: nil)
        if (try? await center.add(req)) != nil { UserDefaults.standard.set(info.version, forKey: key) }
    }

    /// 진단용: 알림 권한이 어떤 상태인지
    func permission() async -> String {
        guard canNotify else { return "번들 없음" }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional: return "허용"
        case .denied: return "거절"
        case .notDetermined: return "아직 안 정함"
        @unknown default: return "모름"
        }
    }

    /// 알림을 눌렀을 때: 이 맥에서 도는 버전이면 메뉴 줄과 같이 내려받기 주소를, 아니면 소프트웨어 업데이트를 연다
    func open(url: String?, runsHere: Bool) {
        guard runsHere else { NSWorkspace.shared.open(Self.softwareUpdate); return }
        guard let link = url.flatMap(URL.init(string:)), Self.trusted(link) else { return }
        Reporting.signal("update.clicked")
        NSWorkspace.shared.open(link)
    }

    /// 이 맥의 macOS "주.부.패치"
    nonisolated static var thisOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 내려받기 주소는 소개 사이트의 /download/(GitHub 릴리스로 넘김)와 GitHub 릴리스만 연다.
    /// version.json이 바뀌어도 다른 곳으로 보내지 못하게
    nonisolated static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.port == nil else { return false }
        switch url.host {
        case "jupjup.d-t-it.com": return url.path.hasPrefix("/download/")
        case "github.com": return url.path.hasPrefix("/nemodleo/jupjup/releases/")
        default: return false
        }
    }
}

/// 알림 센터 델리게이트. 앱이 앞에 있어도 배너로 보이게, 누르면 UpdateChecker.open
final class UpdateNotices: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let url = info["url"] as? String, here = info["runsHere"] as? Bool ?? true
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { MainActor.assumeIsolated { UpdateChecker.shared.open(url: url, runsHere: here) } }
        }
        done()
    }
}

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
    /// 피드의 min_os. 없으면 어느 macOS에서나 돈다
    var minOS: String? = nil
    /// 이 맥의 macOS에서 도는지. 아니면 메뉴 줄이 "macOS 26부터"가 되고 내려받기 주소를 열지 않는다
    var runsHere = true
}
