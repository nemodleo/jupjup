import AppKit
import Carbon.HIToolbox

// 바꿀 수 있는 전역 단축키. Carbon 핫키라 손쉬운 사용 권한이 필요 없다.

struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonMods: UInt32

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_2), carbonMods: UInt32(cmdKey | shiftKey))

    /// 화면에 보일 키 조각: ⌃ ⌥ ⇧ ⌘ 순서 + 키 이름
    var caps: [String] {
        var out: [String] = []
        if carbonMods & UInt32(controlKey) != 0 { out.append("⌃") }
        if carbonMods & UInt32(optionKey) != 0 { out.append("⌥") }
        if carbonMods & UInt32(shiftKey) != 0 { out.append("⇧") }
        if carbonMods & UInt32(cmdKey) != 0 { out.append("⌘") }
        out.append(Self.keyName(keyCode))
        return out
    }

    var text: String { caps.joined() }

    init(keyCode: UInt32, carbonMods: UInt32) {
        self.keyCode = keyCode
        self.carbonMods = carbonMods
    }

    /// 누른 키에서 단축키를 만든다. ⌘·⌃·⌥ 중 하나가 없으면(기능 키 제외) 쓰지 않는다.
    init?(event e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        let code = UInt32(e.keyCode)
        let strong = f.contains(.command) || f.contains(.control) || f.contains(.option)
        guard strong || Self.functionKeys[code] != nil else { return nil }
        self.init(keyCode: code, carbonMods: m)
    }

    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]

    /// 한글 입력 상태여도 자판에 적힌 글자로 보이게 ANSI 배열을 직접 쓴다
    private static let ansi: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    static func keyName(_ code: UInt32) -> String {
        functionKeys[code] ?? ansi[code] ?? "#\(code)"
    }
}

@MainActor
final class HotKeyCenter {
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    /// 등록. 다른 앱이 이미 쓰는 조합이면 false
    @discardableResult
    func register(_ s: Shortcut) -> Bool {
        installHandler()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4A55504A), id: 1) // 'JUPJ'
        let status = RegisterEventHotKey(s.keyCode, s.carbonMods, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<HotKeyCenter>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { me.onPress?() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
