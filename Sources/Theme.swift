import AppKit

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    var hex: Int {
        let c = usingColorSpace(.sRGB) ?? self
        func b(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return b(c.redComponent) << 16 | b(c.greenComponent) << 8 | b(c.blueComponent)
    }
}

/// 화면 효과(키캡·물결) 색 묶음. 어두운 화면 위에서 선명하되 눈이 아프지 않은 톤만 쓴다.
struct Theme {
    let id: String
    let name: String
    let accent: NSColor        // 키 입력 빛, 왼쪽 클릭 물결
    let alt: NSColor           // 오른쪽·기타 클릭 물결
    let hangul: NSColor        // 한 전환 빛
    let english: NSColor       // 영 전환 빛
    let face: NSColor          // 키캡 윗면
    let body: NSColor          // 키캡 몸통(테 안쪽)
    let rim: NSColor           // 평소 테 색
    let hangulText: NSColor    // 키캡에 뜨는 '한'
    let englishText: NSColor   // 키캡에 뜨는 'A'

    static let presets: [Theme] = [
        Theme(id: "amber", name: "앰버 (기본)",
              accent: .init(hex: 0xFFC56B), alt: .init(hex: 0x7CC7FF), hangul: .init(hex: 0xFF7FA8), english: .init(hex: 0x7CC7FF),
              face: .init(hex: 0xF5E8CC), body: .init(hex: 0x1A171F), rim: .init(hex: 0xC7C7C7),
              hangulText: .init(hex: 0xBF2E61), englishText: .init(hex: 0x1F6BB3)),
        Theme(id: "mint", name: "민트",
              accent: .init(hex: 0x6EE7B7), alt: .init(hex: 0xB4A7FF), hangul: .init(hex: 0xFF9EC4), english: .init(hex: 0x7DD3FC),
              face: .init(hex: 0xE6F5EE), body: .init(hex: 0x14201C), rim: .init(hex: 0xA9C7BB),
              hangulText: .init(hex: 0xB8326A), englishText: .init(hex: 0x1D6FA3)),
        Theme(id: "lavender", name: "라벤더",
              accent: .init(hex: 0xC4A7FF), alt: .init(hex: 0x7FE0D6), hangul: .init(hex: 0xFF9EC4), english: .init(hex: 0x8EC5FF),
              face: .init(hex: 0xEEE8FA), body: .init(hex: 0x1B1726), rim: .init(hex: 0xB9B0CF),
              hangulText: .init(hex: 0xA8326E), englishText: .init(hex: 0x3A5FB8)),
        Theme(id: "sakura", name: "벚꽃",
              accent: .init(hex: 0xFF9EC4), alt: .init(hex: 0x9AD8FF), hangul: .init(hex: 0xFF7FA8), english: .init(hex: 0x8EC5FF),
              face: .init(hex: 0xFBE9EF), body: .init(hex: 0x241820), rim: .init(hex: 0xD6B4C1),
              hangulText: .init(hex: 0xB8326A), englishText: .init(hex: 0x2F6CB0)),
        Theme(id: "ocean", name: "바다",
              accent: .init(hex: 0x5ED3F3), alt: .init(hex: 0xA7F3D0), hangul: .init(hex: 0xFF9EC4), english: .init(hex: 0x5ED3F3),
              face: .init(hex: 0xE3F2F7), body: .init(hex: 0x0F1C24), rim: .init(hex: 0x9FBFCC),
              hangulText: .init(hex: 0xB03A6E), englishText: .init(hex: 0x13698A)),
        Theme(id: "lime", name: "라임",
              accent: .init(hex: 0xB8E994), alt: .init(hex: 0xFFCB6B), hangul: .init(hex: 0xFF9EC4), english: .init(hex: 0x82AAFF),
              face: .init(hex: 0xEEF6E4), body: .init(hex: 0x161D14), rim: .init(hex: 0xB4C7A6),
              hangulText: .init(hex: 0xB0386C), englishText: .init(hex: 0x2D5FB0)),
        Theme(id: "night", name: "다크 키캡",
              accent: .init(hex: 0xF5E1B8), alt: .init(hex: 0x8EC5FF), hangul: .init(hex: 0xFF9EC4), english: .init(hex: 0x8EC5FF),
              face: .init(hex: 0x2B2832), body: .init(hex: 0x111014), rim: .init(hex: 0x6E6A78),
              hangulText: .init(hex: 0xFF9EC4), englishText: .init(hex: 0x8EC5FF)),
    ]

    /// 직접 고른 강조색: 앰버를 바탕으로 강조색만 바꾸고, 오른쪽 클릭색은 반대편 색상으로 만든다.
    static func custom(accent: NSColor) -> Theme {
        let base = presets[0]
        let c = accent.usingColorSpace(.sRGB) ?? accent
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let alt = NSColor(hue: (h + 0.5).truncatingRemainder(dividingBy: 1), saturation: min(s, 0.6),
                          brightness: max(b, 0.9), alpha: 1)
        return Theme(id: "custom", name: "직접 고른 색", accent: c, alt: alt, hangul: base.hangul, english: base.english,
                     face: base.face, body: base.body, rim: base.rim,
                     hangulText: base.hangulText, englishText: base.englishText)
    }
}
