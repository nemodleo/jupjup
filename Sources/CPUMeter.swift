import Foundation
import Darwin

/// 맥 전체 CPU가 얼마나 바쁜지. 바쁘면 글자 인식이 느려질 수 있다고 미리 알린다.
struct CPUMeter {
    private var last: (busy: Double, total: Double)?

    private static func ticks() -> (busy: Double, total: Double)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0), sys = Double(info.cpu_ticks.1), idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    /// 기준점 찍기(단축키를 누른 순간)
    mutating func mark() { last = Self.ticks() }

    /// 기준점 이후 CPU 사용률 0…1. 기준점이 없거나 너무 짧으면 nil
    func usage() -> Double? {
        guard let a = last, let b = Self.ticks(), b.total - a.total > 0 else { return nil }
        return (b.busy - a.busy) / (b.total - a.total)
    }

    /// 바쁘면 보여 줄 사용률(%), 아니면 nil. CPU 80% 이상 또는 1분 부하가 코어 수의 2배 이상
    func busyPercent() -> Int? {
        var load = [Double](repeating: 0, count: 3)
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        let overloaded = getloadavg(&load, 3) > 0 && load[0] >= cores * 2
        let u = usage() ?? 0
        guard u >= 0.8 || overloaded else { return nil }
        return Int((max(u, overloaded ? 0.95 : 0) * 100).rounded())
    }
}
