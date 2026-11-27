import Foundation

// 새 버전 알림의 규칙. 다른 소스에 기대지 않는 순수 함수만 둔다 — tools/update_test.swift가 이 파일 하나와 함께 컴파일한다

/// "1.10" > "1.9", "1.0.1" > "1.0". 숫자가 아닌 꼬리(-beta 등)는 무시
func isNewer(_ a: String, than b: String) -> Bool {
    func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

/// 이 맥에서 도는지: min_os가 없거나 이 맥의 macOS가 그 이상
func runs(minOS: String?, on os: String) -> Bool {
    guard let m = minOS, !m.isEmpty else { return true }
    return !isNewer(m, than: os)
}

/// 화면에 보일 macOS 버전. "26.0" → "26", "15.6" → "15.6"
func osLabel(_ minOS: String) -> String {
    var parts = minOS.split(separator: ".").map(String.init)
    while parts.count > 1, parts.last == "0" { parts.removeLast() }
    return parts.joined(separator: ".")
}

/// 알릴지: 확인이 켜져 있고, 그 버전을 아직 안 알렸을 때만(버전마다 한 번)
func shouldNotify(version: String, notified: String?, checkOn: Bool) -> Bool { checkOn && version != notified }

/// 지금 띄워도 되는지: 바쁘지 않고, 마지막으로 바빴던 때(고르기 화면·토스트)에서 5초가 지났을 때
func canFire(now: Date, lastBusy: Date?, busy: Bool) -> Bool {
    guard !busy else { return false }
    guard let lastBusy else { return true }
    return now.timeIntervalSince(lastBusy) >= 5
}
