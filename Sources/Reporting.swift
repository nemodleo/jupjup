import Foundation
import Sentry
import TelemetryDeck

// 리포트: 오류는 Sentry, 횟수는 TelemetryDeck. 글 내용·화면·좌표는 절대 보내지 않는다.
// 설정 '오류·사용 통계 보내기'(기본 켬)를 끄면 아무것도 보내지 않는다.
// 키는 Info.plist(JJSentryDSN, JJTelemetryAppID)에서 읽고, 비어 있으면 그 쪽은 조용히 꺼진다.

@MainActor
enum Reporting {
    private static var started = false
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var sentryDSN: String { info["JJSentryDSN"] as? String ?? "" }
    static var telemetryAppID: String { info["JJTelemetryAppID"] as? String ?? "" }
    /// 키가 하나라도 있으면 보낼 곳이 있다
    static var configured: Bool { !sentryDSN.isEmpty || !telemetryAppID.isEmpty }
    /// 시험 빌드: 대시보드에서 테스트 신호로 구분된다
    static var isTest: Bool { ProcessInfo.processInfo.environment["JJ_REPORT_TEST"] == "1" }

    static func start() {
        guard Settings.shared.reports, !started, configured else { return }
        started = true
        if !sentryDSN.isEmpty {
            SentrySDK.start { o in
                o.dsn = sentryDSN
                o.environment = isTest ? "test" : "production"
                o.enableCrashHandler = true
                o.enableAutoSessionTracking = true
                o.sendDefaultPii = false
                o.tracesSampleRate = 0
            }
        }
        if !telemetryAppID.isEmpty {
            let cfg = TelemetryDeck.Config(appID: telemetryAppID)
            cfg.testMode = isTest
            TelemetryDeck.initialize(config: cfg)
        }
        signal("app.launched", ["language": Settings.shared.language.resolved.rawValue,
                                "mode": Settings.shared.fastMode ? "fast" : "accurate",
                                "chip": chip])
    }

    static func stop() {
        guard started else { return }
        if !sentryDSN.isEmpty { SentrySDK.close() }
        started = false
    }

    /// 횟수 신호. name은 "capture.done"처럼 점으로 나눈 이름, params는 짧은 분류값만
    static func signal(_ name: String, _ params: [String: String] = [:]) {
        guard started, Settings.shared.reports, !telemetryAppID.isEmpty else { return }
        TelemetryDeck.signal(name, parameters: params)
    }

    /// 죽지는 않았지만 알아야 할 오류(권한 실패 등)
    static func error(_ name: String, _ tags: [String: String] = [:]) {
        guard started, Settings.shared.reports, !sentryDSN.isEmpty else { return }
        SentrySDK.capture(message: name) { scope in
            scope.setLevel(.warning)
            for (k, v) in tags { scope.setTag(value: v, key: k) }
        }
    }

    // MARK: 분류값(정확한 숫자 대신 구간만 보낸다)

    static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: "0"
        case 1: "1"
        case 2...5: "2-5"
        case 6...20: "6-20"
        case 21...100: "21-100"
        default: "100+"
        }
    }

    static func seconds(_ s: Double) -> String {
        switch s {
        case ..<0.5: "<0.5"
        case ..<1: "<1"
        case ..<2: "<2"
        case ..<5: "<5"
        case ..<10: "<10"
        default: "10+"
        }
    }

    static var chip: String {
        #if arch(arm64)
        return "apple"
        #else
        return "intel"
        #endif
    }
}
