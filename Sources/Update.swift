import Foundation

/// 새 버전 알림. 소개 사이트의 version.json을 켤 때와 하루에 한 번 본다.
/// 보내는 건 쿠키·식별자 없는 GET 하나. 메뉴의 "새 버전 확인"을 끄면 아예 안 본다.
/// 자동 설치는 하지 않는다(공증 전이라). 새 버전이 있으면 메뉴 맨 위에 "새 버전 1.1 · 내려받기"가 뜬다.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Feed: Decodable { let version: String; let url: String }

    /// 시험할 때는 `defaults write com.nemo.jupjup updateURL file:///…/version.json`
    var feed: URL {
        UserDefaults.standard.string(forKey: "updateURL").flatMap(URL.init(string:)) ?? URL(string: "https://jupjup.d-t-it.com/version.json")!
    }
    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private var timer: Timer?
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral // 쿠키·캐시 없음
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    func start() {
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
            guard let f = try? JSONDecoder().decode(Feed.self, from: data), let link = URL(string: f.url) else { return }
            let newer = Self.isNewer(f.version, than: mine)
            if newer, Settings.shared.update?.version != f.version { Reporting.signal("update.available", ["version": f.version]) }
            Settings.shared.update = newer ? .init(version: f.version, url: link) : nil
        }
    }

    /// "1.10" > "1.9", "1.0.1" > "1.0". 숫자가 아닌 꼬리(-beta 등)는 무시
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}
