import AppKit
import Carbon.HIToolbox

/// 키보드·마우스 이벤트를 '듣기만' 하는 이벤트 탭(listen-only).
/// 이벤트를 바꾸거나 막지 않고, 어떤 키인지 저장·전송하지 않는다 — 키코드는 소리 종류를 고르는 데만 쓴다.
/// 키보드는 '입력 모니터링' 권한이 있어야 들어온다. 암호 입력란(보안 입력 모드)에서는 macOS가 아예 전달하지 않는다.
final class InputTap {
    enum Event {
        case keyDown(code: Int64, isRepeat: Bool, flags: CGEventFlags)
        case keyUp(code: Int64)
        case flags(code: Int64, flags: CGEventFlags)
        case mouseDown(button: Int, at: CGPoint)
        case mouseUp(button: Int, at: CGPoint)
        case scroll(delta: Double, continuous: Bool, momentum: Bool)
    }

    var handler: (Event) -> Void = { _ in }
    private var keyTap: CFMachPort?
    private var mouseTap: CFMachPort?

    var keyboardActive: Bool { keyTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        if mouseTap == nil {
            let mask = mask([.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel])
            mouseTap = install(mask)
        }
        if keyTap == nil, CGPreflightListenEventAccess() {
            keyTap = install(mask([.keyDown, .keyUp, .flagsChanged]))
        }
    }

    private func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    private func install(_ mask: CGEventMask) -> CFMachPort? {
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: inputTapCallback, userInfo: me) else {
            NSLog("Tajagi: tapCreate failed (mask %llx)", mask)
            return nil
        }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    fileprivate func receive(_ type: CGEventType, _ e: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 시스템이 탭을 꺼버리면 다시 켠다
            if let t = keyTap { CGEvent.tapEnable(tap: t, enable: true) }
            if let t = mouseTap { CGEvent.tapEnable(tap: t, enable: true) }
        case .keyDown:
            handler(.keyDown(code: e.getIntegerValueField(.keyboardEventKeycode),
                             isRepeat: e.getIntegerValueField(.keyboardEventAutorepeat) != 0, flags: e.flags))
        case .keyUp:
            handler(.keyUp(code: e.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            handler(.flags(code: e.getIntegerValueField(.keyboardEventKeycode), flags: e.flags))
        case .leftMouseDown: handler(.mouseDown(button: 0, at: e.location))
        case .rightMouseDown: handler(.mouseDown(button: 1, at: e.location))
        case .otherMouseDown: handler(.mouseDown(button: 2, at: e.location))
        case .leftMouseUp: handler(.mouseUp(button: 0, at: e.location))
        case .rightMouseUp: handler(.mouseUp(button: 1, at: e.location))
        case .otherMouseUp: handler(.mouseUp(button: 2, at: e.location))
        case .scrollWheel:
            let continuous = e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let dy = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let momentum = e.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
            handler(.scroll(delta: abs(dy) + abs(dx), continuous: continuous, momentum: momentum))
        default: break
        }
    }
}

private func inputTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue().receive(type, event)
    }
    return Unmanaged.passUnretained(event)
}

/// 현재 입력 소스가 한글인지 감시한다(한/영 전환 감지).
final class InputSourceWatcher {
    private(set) var isKorean: Bool
    var onChange: (Bool) -> Void = { _ in }

    init() {
        isKorean = InputSourceWatcher.currentIsKorean()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.check() }
    }

    private func check() {
        let now = InputSourceWatcher.currentIsKorean()
        guard now != isKorean else { return }
        isKorean = now
        onChange(now)
    }

    static func currentIsKorean() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return false }
        let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        // 한글 입력기 안의 '로마자' 모드는 영어로 취급
        return id.contains("Korean") && !id.hasSuffix("Roman")
    }
}

/// 키가 키보드 어디쯤 있는지(-1 왼쪽 … +1 오른쪽) — 소리를 그 위치에서 들리게 한다.
enum KeyLayout {
    private static let rows: [[Int64]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],
        [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],
        [56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 60],
    ]
    private static let table: [Int64: Double] = {
        var t: [Int64: Double] = [:]
        for row in rows {
            for (i, k) in row.enumerated() { t[k] = Double(i) / Double(row.count - 1) * 2 - 1 }
        }
        t[49] = 0                                   // 스페이스
        for k: Int64 in [123, 125, 124, 126, 117, 115, 119, 116, 121] { t[k] = 0.9 }  // 화살표·편집키
        t[55] = -0.5; t[58] = -0.75; t[59] = -0.9; t[63] = -0.95   // 왼쪽 ⌘⌥⌃fn
        t[54] = 0.5; t[61] = 0.65                                  // 오른쪽 ⌘⌥
        return t
    }()

    static func position(_ code: Int64) -> Double { table[code] ?? 0 }
}
