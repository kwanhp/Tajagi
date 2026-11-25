import AppKit
import ServiceManagement

/// 설정(UserDefaults)
final class Settings {
    private let d = UserDefaults.standard
    init() {
        d.register(defaults: [
            "enabled": true, "volume": 0.6, "keySounds": true, "marginBell": false, "bellColumn": 65,
            "hangulSound": true, "mouseSounds": true, "scrollSounds": true, "keyFlash": true, "clickRipple": true,
            "theme": "amber", "customAccent": 0xFFC56B,
        ])
    }
    subscript(key: String) -> Bool {
        get { d.bool(forKey: key) }
        set { d.set(newValue, forKey: key) }
    }
    var volume: Float {
        get { d.float(forKey: "volume") }
        set { d.set(newValue, forKey: "volume") }
    }
    var bellColumn: Int { d.integer(forKey: "bellColumn") }
    var themeID: String {
        get { d.string(forKey: "theme") ?? "amber" }
        set { d.set(newValue, forKey: "theme") }
    }
    var customAccent: Int {
        get { d.integer(forKey: "customAccent") }
        set { d.set(newValue, forKey: "customAccent") }
    }
    var theme: Theme {
        if themeID == "custom" { return .custom(accent: NSColor(hex: customAccent)) }
        return Theme.presets.first { $0.id == themeID } ?? Theme.presets[0]
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private var audio: AudioOut!
    private let tap = InputTap()
    private var source: InputSourceWatcher!
    private var flash: KeyFlash!
    private var ripples: Ripples!

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var toggleItems: [String: NSMenuItem] = [:]
    private var enabledItem: NSMenuItem!
    private var permItem: NSMenuItem!
    private var relaunchItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var themeItems: [NSMenuItem] = []
    private var customThemeItem: NSMenuItem!
    private var lastThemePreview: CFTimeInterval = 0

    // 상태
    private var column = 0              // 마지막 줄바꿈 이후 글자 수(여백 벨용)
    private var lastRepeat: CFTimeInterval = 0
    private var lastScroll: CFTimeInterval = 0
    private var scrollAccum = 0.0
    private var heldFlags: UInt64 = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        audio = AudioOut()
        audio.master = settings.volume
        flash = KeyFlash(theme: settings.theme)
        ripples = Ripples()
        source = InputSourceWatcher()
        source.onChange = { [weak self] korean in self?.inputSourceChanged(korean) }

        tap.handler = { [weak self] e in self?.handle(e) }
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }   // 시스템이 권한 안내를 띄운다
        tap.start()

        buildMenu()
        refreshMenu()
        // 권한을 나중에 켰을 때 다시 시도
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.tap.keyboardActive, CGPreflightListenEventAccess() { self.tap.start(); self.refreshMenu() }
        }
    }

    // MARK: 이벤트 → 소리/표시

    private func now() -> CFTimeInterval { CACurrentMediaTime() }

    private func handle(_ e: InputTap.Event) {
        switch e {
        case let .keyDown(code, isRepeat, flags):
            // ⌃⌥M: 음소거 토글
            if code == 46, flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand) {
                if !isRepeat { toggleEnabled() }
                return
            }
            guard settings["enabled"] else { return }
            if [79, 102, 104].contains(code) { return }   // 한/영 키 자체는 조용히 — 전환 소리가 대신 난다
            if isRepeat { return }   // 진짜 키보드처럼: 누르고 있는 동안은 소리 없음
            let shortcut = flags.contains(.maskCommand) || flags.contains(.maskControl)
            var sound = Sound.key
            var heavy = false
            switch code {
            case 36, 76: sound = .wide; heavy = true; column = 0
            case 49: sound = .space; heavy = true; column += 1
            case 51: sound = .wide; column = max(0, column - 1)
            case 117, 48, 53, 96...101, 103, 105...111, 113...116, 118...126: break
            default: if !shortcut { column += 1 }
            }
            if settings["keySounds"] {
                var g: Float = Float.random(in: 0.86...1.0)
                if shortcut { g *= 0.85 }
                audio.play(sound, gain: g, pan: Float(KeyLayout.position(code) * 0.5))
                if settings["marginBell"], !isRepeat, !shortcut, column == settings.bellColumn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in self?.audio.play(.bell, gain: 0.9, pan: 0.45) }
                }
            }
            if settings["keyFlash"] { flash.pulse(heavy: heavy) }

        case let .keyUp(code):
            guard settings["enabled"], settings["keySounds"], ![79, 102, 104].contains(code) else { return }
            let up: Sound = code == 49 ? .spaceUp : [36, 76, 51].contains(code) ? .wideUp : .keyUp
            audio.play(up, gain: Float.random(in: 0.8...1.0), pan: Float(KeyLayout.position(code) * 0.5))

        case let .flags(code, flags):
            guard settings["enabled"] else { return }
            let raw = flags.rawValue
            // 키별 비트(왼/오른쪽 구분)
            let bit: UInt64
            switch code {
            case 56: bit = 0x02      // 왼쪽 shift
            case 60: bit = 0x04      // 오른쪽 shift
            case 55: bit = 0x08      // 왼쪽 ⌘
            case 54: bit = 0x10      // 오른쪽 ⌘
            case 58: bit = 0x20      // 왼쪽 ⌥
            case 61: bit = 0x40      // 오른쪽 ⌥
            case 59: bit = 0x01      // 왼쪽 ⌃
            case 62: bit = 0x2000    // 오른쪽 ⌃
            case 63: bit = CGEventFlags.maskSecondaryFn.rawValue
            case 57: bit = CGEventFlags.maskAlphaShift.rawValue
            default: return
            }
            let down = raw & bit != 0
            let wasDown = heldFlags & bit != 0
            heldFlags = down ? heldFlags | bit : heldFlags & ~bit
            guard down != wasDown || code == 57, settings["keySounds"] else { return }
            let pan = Float(KeyLayout.position(code) * 0.5)
            switch code {
            case 56, 60: audio.play(down ? .wide : .wideUp, gain: 0.9, pan: pan)        // 시프트 = 스테빌라이저 키
            case 57: audio.play(.key, pan: pan)                                         // Caps Lock: 토글마다 한 번
            default: audio.play(down ? .key : .keyUp, gain: 0.85, pan: pan)             // ⌘⌥⌃fn
            }
            if down, settings["keyFlash"], code == 56 || code == 60 || code == 57 { flash.pulse() }

        case let .mouseDown(button, p):
            column = 0
            guard settings["enabled"] else { return }
            if settings["mouseSounds"] { audio.play(button == 0 ? .typeClick : .typeRight, gain: 0.8, pan: pan(for: p)) }
            if settings["clickRipple"] { ripples.show(at: p, color: button == 0 ? settings.theme.accent : settings.theme.alt) }

        case let .mouseUp(_, p):
            guard settings["enabled"], settings["mouseSounds"] else { return }
            audio.play(.typeRelease, gain: 0.8, pan: pan(for: p))

        case let .scroll(delta, continuous, momentum):
            guard settings["enabled"], settings["scrollSounds"], delta > 0 else { return }
            var fire = !continuous
            if continuous {
                scrollAccum += delta
                if scrollAccum >= 24 { scrollAccum = min(scrollAccum - 24, 24); fire = true }
            }
            guard fire, now() - lastScroll > 0.024 else { return }
            lastScroll = now()
            audio.play(.scrollTick, gain: momentum ? 0.5 : 0.9, pan: pan(for: NSEvent.mouseLocation, flipped: false))
        }
    }

    private func pan(for p: CGPoint, flipped: Bool = true) -> Float {
        let screens = NSScreen.screens
        let minX = screens.map { $0.frame.minX }.min() ?? 0
        let maxX = screens.map { $0.frame.maxX }.max() ?? 1
        let x = (p.x - minX) / max(1, maxX - minX)
        return Float((x - 0.5) * 0.7)
    }

    private func inputSourceChanged(_ korean: Bool) {
        guard settings["enabled"] else { return }
        if settings["hangulSound"] { audio.play(korean ? .toHangul : .toEnglish) }
        if settings["keyFlash"] { flash.showMode(korean: korean) }
    }

    // MARK: 메뉴

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self

        enabledItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(volumeItem())
        menu.addItem(.separator())

        addToggle("keySounds", "키보드 소리 (묵직한 기계식)")
        addToggle("marginBell", "여백 벨 (\(settings.bellColumn)번째 글자에서 '띵')")
        addToggle("hangulSound", "한/영 전환 소리")
        addToggle("mouseSounds", "클릭 소리 (타자기)")
        addToggle("scrollSounds", "스크롤 틱 (타자기 노브)")
        menu.addItem(.separator())
        addToggle("keyFlash", "키 입력 표시 (화면 아래 키캡)")
        addToggle("clickRipple", "클릭 물결")
        menu.addItem(themeMenuItem())
        menu.addItem(.separator())

        let preview = NSMenuItem(title: "소리 미리듣기", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in Sound.allCases {
            let it = NSMenuItem(title: s.label, action: #selector(previewSound(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s.rawValue
            sub.addItem(it)
        }
        preview.submenu = sub
        menu.addItem(preview)
        menu.addItem(.separator())

        permItem = NSMenuItem(title: "⚠️ 키보드 소리: 입력 모니터링 권한 필요 — 설정 열기", action: #selector(openPermission), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        relaunchItem = NSMenuItem(title: "권한을 켰으면: 다시 실행", action: #selector(relaunch), keyEquivalent: "")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        loginItem = NSMenuItem(title: "로그인 시 자동 시작", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func themeMenuItem() -> NSMenuItem {
        let top = NSMenuItem(title: "테마 색상", action: nil, keyEquivalent: "")
        top.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        let sub = NSMenu()
        for t in Theme.presets {
            let it = NSMenuItem(title: t.name, action: #selector(pickTheme(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t.id
            it.image = swatch(t)
            themeItems.append(it)
            sub.addItem(it)
        }
        sub.addItem(.separator())
        customThemeItem = NSMenuItem(title: "강조색 직접 고르기…", action: #selector(pickCustomColor), keyEquivalent: "")
        customThemeItem.target = self
        sub.addItem(customThemeItem)
        top.submenu = sub
        return top
    }

    /// 메뉴에 보이는 작은 색 견본: 키캡 + 강조색 + 오른쪽 클릭색
    private func swatch(_ t: Theme) -> NSImage {
        let img = NSImage(size: NSSize(width: 38, height: 14), flipped: false) { _ in
            func dot(_ x: CGFloat, _ fill: NSColor, _ stroke: NSColor? = nil) {
                let p = NSBezierPath(ovalIn: NSRect(x: x, y: 1, width: 12, height: 12))
                fill.setFill(); p.fill()
                if let stroke { stroke.setStroke(); p.lineWidth = 1.5; p.stroke() }
            }
            dot(1, t.face, t.body)
            dot(13, t.accent)
            dot(25, t.alt)
            return true
        }
        img.isTemplate = false
        return img
    }

    private func applyTheme(preview: Bool) {
        let t = settings.theme
        flash.theme = t
        refreshMenu()
        guard preview else { return }
        // 바꾼 색을 바로 보여준다: 키캡 깜박 + 마우스 자리에 물결 두 번(왼쪽·오른쪽 클릭색)
        flash.pulse(heavy: true)
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x, y: (NSScreen.screens.first?.frame.height ?? 0) - m.y)
        ripples.show(at: p, color: t.accent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in self?.ripples.show(at: p, color: t.alt) }
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.themeID = id
        applyTheme(preview: true)
    }

    @objc private func pickCustomColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = settings.theme.accent
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        settings.customAccent = sender.color.hex
        settings.themeID = "custom"
        // 슬라이더를 끄는 동안 물결이 쏟아지지 않게 0.25초에 한 번만 미리보기
        let t = now()
        applyTheme(preview: t - lastThemePreview > 0.25)
        if t - lastThemePreview > 0.25 { lastThemePreview = t }
    }

    private func addToggle(_ key: String, _ title: String) {
        let it = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = key
        toggleItems[key] = it
        menu.addItem(it)
    }

    private func volumeItem() -> NSMenuItem {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        let l = NSTextField(labelWithString: "음량")
        l.frame = NSRect(x: 18, y: 6, width: 40, height: 18)
        let s = NSSlider(value: Double(settings.volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        s.frame = NSRect(x: 58, y: 4, width: 176, height: 22)
        s.isContinuous = true
        v.addSubview(l); v.addSubview(s)
        let it = NSMenuItem()
        it.view = v
        return it
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        let on = settings["enabled"]
        enabledItem.title = on ? "Tajagi 소리 켜짐  (⌃⌥M 끄기)" : "Tajagi 소리 꺼짐  (⌃⌥M 켜기)"
        enabledItem.state = on ? .on : .off
        for (k, it) in toggleItems { it.state = settings[k] ? .on : .off }
        let tid = settings.themeID
        for it in themeItems { it.state = (it.representedObject as? String) == tid ? .on : .off }
        customThemeItem.state = tid == "custom" ? .on : .off
        customThemeItem.image = tid == "custom" ? swatch(settings.theme) : nil
        let perm = CGPreflightListenEventAccess()
        permItem.isHidden = perm && tap.keyboardActive
        relaunchItem.isHidden = tap.keyboardActive
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
        if let b = statusItem.button {
            let name = on ? "keyboard" : "keyboard.badge.ellipsis"
            b.image = NSImage(systemSymbolName: name, accessibilityDescription: "타자기")
            b.image?.isTemplate = true
            b.toolTip = on ? "타자기 소리 켜짐" : "타자기 소리 꺼짐"
        }
    }

    @objc private func toggleEnabled() {
        settings["enabled"].toggle()
        if settings["enabled"] { audio.play(.carriage, gain: 0.7) }
        refreshMenu()
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let k = sender.representedObject as? String else { return }
        settings[k].toggle()
        refreshMenu()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        settings.volume = Float(sender.doubleValue)
        audio.master = settings.volume
        if now() - lastRepeat > 0.12 { lastRepeat = now(); audio.play(.key) }
    }

    @objc private func previewSound(_ sender: NSMenuItem) {
        guard let r = sender.representedObject as? String, let s = Sound(rawValue: r) else { return }
        audio.play(s)
        if s == .toHangul || s == .toEnglish { flash.showMode(korean: s == .toHangul) }
    }

    @objc private func openPermission() {
        CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleLoginItem() {
        let svc = SMAppService.mainApp
        do {
            switch svc.status {
            case .enabled: try svc.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try svc.register()
                if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSLog("Tajagi login item error: \(error)")
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshMenu()
    }
}
