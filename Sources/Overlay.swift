import AppKit
import QuartzCore

/// 투명·클릭 통과 오버레이 창
private func makeOverlayPanel(size: CGSize) -> NSPanel {
    let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.ignoresMouseEvents = true
    p.isReleasedWhenClosed = false
    p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    p.contentView = NSView(frame: NSRect(origin: .zero, size: size))
    p.contentView!.wantsLayer = true
    return p
}


/// 화면 아래쪽 가운데의 옛날 타자기 둥근 키캡. 키를 치면 '눌리며' 깜박인다. 어떤 키인지는 절대 표시하지 않는다.
/// 한/영 전환 때만 '한' / 'A' 글자를 잠깐 띄운다.
final class KeyFlash {
    private let size = CGSize(width: 76, height: 76)
    private let panel: NSPanel
    private let cap = CALayer()      // 눌리는 부분(링 + 면)
    private let ring = CALayer()
    private let face = CALayer()
    private let label = CATextLayer()
    private var hideWork: DispatchWorkItem?
    private var labelWork: DispatchWorkItem?

    /// 바꾸면 키캡 색이 바로 바뀐다
    var theme: Theme { didSet { applyTheme() } }

    init(theme: Theme) {
        self.theme = theme
        panel = makeOverlayPanel(size: size)
        let root = panel.contentView!.layer!
        let d: CGFloat = 52
        cap.frame = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
        root.addSublayer(cap)

        ring.frame = cap.bounds
        ring.cornerRadius = d / 2
        ring.borderWidth = 3
        ring.shadowRadius = 10
        ring.shadowOpacity = 0
        ring.shadowOffset = .zero
        cap.addSublayer(ring)

        let f: CGFloat = d - 14
        face.frame = CGRect(x: 7, y: 7, width: f, height: f)
        face.cornerRadius = f / 2
        cap.addSublayer(face)

        label.frame = CGRect(x: 0, y: (f - 26) / 2 - 1, width: f, height: 28)
        label.alignmentMode = .center
        label.fontSize = 21
        label.font = NSFont.systemFont(ofSize: 21, weight: .bold)
        label.string = ""
        face.addSublayer(label)
        panel.alphaValue = 0
        applyTheme()
    }

    private func applyTheme() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.backgroundColor = theme.body.cgColor
        ring.borderColor = theme.rim.cgColor
        ring.shadowColor = theme.accent.cgColor
        face.backgroundColor = theme.face.cgColor
        CATransaction.commit()
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 22))
        let scale = screen.backingScaleFactor
        label.contentsScale = scale
    }

    private func appear() {
        hideWork?.cancel()
        if panel.alphaValue < 1 || !panel.isVisible {
            place()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.08; panel.animator().alphaValue = 0.92 }
        }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.45; self.panel.animator().alphaValue = 0 },
                                                 completionHandler: { if self.panel.alphaValue == 0 { self.panel.orderOut(nil) } })
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }

    /// 키 하나 — heavy는 리턴/스페이스처럼 큰 키
    func pulse(heavy: Bool = false, color: NSColor? = nil) {
        appear()
        let color = color ?? theme.accent
        let press = CABasicAnimation(keyPath: "transform.scale")
        press.fromValue = heavy ? 0.80 : 0.87
        press.toValue = 1.0
        press.duration = heavy ? 0.22 : 0.14
        press.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cap.add(press, forKey: "press")

        ring.shadowColor = color.cgColor
        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = heavy ? 1.0 : 0.85
        glow.toValue = 0
        glow.duration = heavy ? 0.45 : 0.3
        ring.add(glow, forKey: "glow")

        let rim = CABasicAnimation(keyPath: "borderColor")
        rim.fromValue = color.cgColor
        rim.toValue = theme.rim.cgColor
        rim.duration = 0.25
        ring.add(rim, forKey: "rim")
    }

    /// 한/영 전환 표시
    func showMode(korean: Bool) {
        labelWork?.cancel()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        label.string = korean ? "한" : "A"
        label.foregroundColor = (korean ? theme.hangulText : theme.englishText).cgColor
        CATransaction.commit()
        pulse(heavy: true, color: korean ? theme.hangul : theme.english)
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.label.string = "" ; self?.appear() }
        labelWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: w)
    }
}

/// 클릭한 자리에 퍼지는 물결
final class Ripples {
    private let size = CGSize(width: 110, height: 110)
    private var pool: [NSPanel] = []
    private var next = 0

    init(count: Int = 6) {
        pool = (0..<count).map { _ in makeOverlayPanel(size: size) }
    }

    /// at: CGEvent 좌표(주 화면 왼쪽 위 원점)
    func show(at p: CGPoint, color: NSColor) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let ns = NSPoint(x: p.x, y: primaryH - p.y)
        let panel = pool[next]; next = (next + 1) % pool.count
        panel.setFrameOrigin(NSPoint(x: ns.x - size.width / 2, y: ns.y - size.height / 2))
        let root = panel.contentView!.layer!
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let ring = CAShapeLayer()
        ring.frame = root.bounds
        let r: CGFloat = 38
        ring.path = CGPath(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r, width: 2 * r, height: 2 * r), transform: nil)
        ring.fillColor = color.withAlphaComponent(0.10).cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.5
        ring.shadowColor = color.cgColor
        ring.shadowRadius = 6
        ring.shadowOpacity = 0.8
        ring.shadowOffset = .zero
        ring.opacity = 0
        root.addSublayer(ring)
        panel.orderFrontRegardless()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.15; scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.95; fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.42
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(g, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak panel, weak ring] in
            if ring?.superlayer != nil, ring?.animation(forKey: "ripple") == nil { panel?.orderOut(nil) }
        }
    }
}
