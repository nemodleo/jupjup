// 새 버전 알림 규칙(UpdateRules.swift) 확인. run_tests.sh가 main.swift로 복사해 UpdateRules.swift와 함께 컴파일한다
import Foundation

var fail = 0
func check(_ ok: Bool, _ name: String) {
    if !ok { fail += 1 }
    print("\(ok ? "✓" : "✗") \(name)")
}

// 버전 비교
check(isNewer("1.10", than: "1.9"), "1.10 > 1.9")
check(isNewer("1.0.1", than: "1.0"), "1.0.1 > 1.0")
check(!isNewer("1.0", than: "1.0.0"), "1.0 = 1.0.0")
check(!isNewer("1.2", than: "1.3"), "1.2 < 1.3")
check(isNewer("2.0-beta", than: "1.9"), "2.0-beta > 1.9 (꼬리 무시)")

// 이 맥에서 도는지
check(runs(minOS: nil, on: "15.6.1"), "min_os 없음 → 돎")
check(runs(minOS: "", on: "15.6.1"), "min_os 빈 글 → 돎")
check(runs(minOS: "26.0", on: "26.0.0"), "같음 → 돎")
check(!runs(minOS: "26", on: "15.6.1"), "낮음 → 안 돎")
check(runs(minOS: "15", on: "26.1"), "높음 → 돎")
check(runs(minOS: "26", on: "26.0"), "\"26\" 대 \"26.0\" → 돎")
check(runs(minOS: "26.0", on: "26"), "\"26.0\" 대 \"26\" → 돎")

// 보일 macOS 버전
check(osLabel("26.0") == "26", "osLabel 26.0 → 26")
check(osLabel("15.6") == "15.6", "osLabel 15.6 → 15.6")
check(osLabel("26") == "26", "osLabel 26 → 26")

// 알릴지
check(!shouldNotify(version: "2.0", notified: nil, checkOn: false), "확인 끔 → 안 알림")
check(!shouldNotify(version: "2.0", notified: "2.0", checkOn: true), "이미 알린 버전 → 안 알림")
check(shouldNotify(version: "2.1", notified: "2.0", checkOn: true), "새 버전 → 알림")
check(shouldNotify(version: "2.0", notified: nil, checkOn: true), "처음 → 알림")

// 지금 띄워도 되는지
let now = Date()
check(!canFire(now: now, lastBusy: nil, busy: true), "바쁨 → 미룸")
check(!canFire(now: now, lastBusy: now.addingTimeInterval(-3), busy: false), "바쁨 끝 3초 → 미룸")
check(canFire(now: now, lastBusy: now.addingTimeInterval(-6), busy: false), "바쁨 끝 6초 → 띄움")
check(canFire(now: now, lastBusy: nil, busy: false), "한 번도 안 바쁨 → 띄움")

print(fail == 0 ? "모두 통과" : "\(fail)개 실패")
exit(fail == 0 ? 0 : 1)
