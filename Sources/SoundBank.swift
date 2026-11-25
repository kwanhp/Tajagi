import Foundation

/// 앱에서 쓰는 소리 종류
/// 키보드 = 묵직한 기계식 키보드(누름 + 뗌), 마우스·트랙패드 클릭 = 타자기, 스크롤 = 타자기 플래튼 노브
enum Sound: String, CaseIterable {
    case key, keyUp            // 일반 키
    case wide, wideUp          // 스테빌라이저 키(엔터·백스페이스·시프트)
    case space, spaceUp        // 스페이스바
    case toHangul, toEnglish   // 한/영 전환
    case bell                  // 여백 벨(선택)
    case typeClick             // 클릭 = 타자기 '착'
    case typeRelease           // 클릭 뗌 = 캐리지 '틱'
    case typeRight             // 오른쪽 클릭 = 타자기 스페이스바 '덜컥'
    case scrollTick            // 스크롤 = 플래튼 노브 래칫
    case dragTick              // 드래그 = 캐리지가 랙을 타고 미끄러지는 '스르륵'
    case carriage              // 켤 때 신호음(캐리지 리턴)

    var label: String {
        switch self {
        case .key: return "키 누름"
        case .keyUp: return "키 뗌"
        case .wide: return "엔터·백스페이스·시프트"
        case .wideUp: return "엔터·백스페이스·시프트 뗌"
        case .space: return "스페이스바"
        case .spaceUp: return "스페이스바 뗌"
        case .toHangul: return "한/영 → 한"
        case .toEnglish: return "한/영 → 영"
        case .bell: return "여백 벨"
        case .typeClick: return "클릭 (타자기 타건)"
        case .typeRelease: return "클릭 뗌 (캐리지 틱)"
        case .typeRight: return "오른쪽 클릭"
        case .scrollTick: return "스크롤 틱"
        case .dragTick: return "드래그 (캐리지 랙)"
        case .carriage: return "캐리지 리턴"
        }
    }

    var variants: Int {
        switch self {
        case .key, .keyUp, .typeClick, .dragTick: return 12
        case .wide, .wideUp, .space, .spaceUp, .typeRelease, .typeRight, .scrollTick: return 6
        case .carriage: return 2
        case .bell, .toHangul, .toEnglish: return 1
        }
    }
}

enum SoundBank {
    static func renderAll() -> [Sound: [[Float]]] {
        var out: [Sound: [[Float]]] = [:]
        for s in Sound.allCases {
            out[s] = (0..<s.variants).map { render(s, seed: UInt64(1000 * (Sound.allCases.firstIndex(of: s)! + 1) + $0)) }
        }
        return out
    }

    static func render(_ s: Sound, seed: UInt64) -> [Float] {
        var c = Canvas(seconds: 0.4, seed: seed)

        // MARK: 기계식 키보드
        /// 바닥 침(bottom-out): 슬라이더·키캡이 하우징/보강판에 '도각' — 부드러운 충격 + 키캡 속 공명 + 케이스의 묵직한 저음
        func press(_ c: inout Canvas, _ body: BodySpec, cav: Double, weight: Double, stab: Bool = false) {
            let b = c.body(body, spread: 0.035)
            let t = 0.003 + c.rng.uni() * 0.002
            c.excite(b, at: t, clicks: [(0, 1.0), (0.0007 + c.rng.uni() * 0.0006, 0.32)], width: 0.00015)
            if stab {   // 긴 키는 양 끝이 살짝 엇갈려 닿는다 '도-각'
                c.excite(b, at: t + 0.0018 + c.rng.uni() * 0.0015, clicks: [(0, 0.55)], width: 0.0002)
            }
            c.cavity(at: t, f: cav * c.rng.jit(0.06), q: 0.9, tau: stab ? 0.011 : 0.008, amp: 0.30)
            c.thud(at: t, amp: weight * 0.45, cutoff: stab ? 320 : 400, tau: stab ? 0.013 : 0.010)
            c.noise(at: t, dur: 0.004, tau: 0.0010, lo: 1600, hi: 6500, amp: 0.85)   // 플라스틱 윤곽(또각)
        }
        /// 올라옴(top-out): 슬라이더가 윗하우징에 '톡' — 더 가볍고 조금 높게
        func release(_ c: inout Canvas, _ body: BodySpec, cav: Double, weight: Double) {
            let b = c.body(body, spread: 0.04)
            let t = 0.002 + c.rng.uni() * 0.002
            c.excite(b, at: t, clicks: [(0, 0.6)], width: 0.00015)
            c.noise(at: t, dur: 0.003, tau: 0.0008, lo: 1800, hi: 6500, amp: 0.45)
            c.cavity(at: t, f: cav * 1.45 * c.rng.jit(0.06), q: 0.9, tau: 0.005, amp: 0.25)
            c.thud(at: t, amp: weight * 0.5, cutoff: 500, tau: 0.007)
        }

        // MARK: 타자기(클릭·스크롤용)
        func escapement(_ c: inout Canvas, at t: Double, amp: Double, clicks: Int = 2) {
            let es = c.body(Machine.escape, spread: 0.03)
            var cl: [(Double, Double)] = [(0, amp)]
            if clicks > 1 { cl.append((0.0032 + c.rng.uni() * 0.0012, amp * 0.65)) }
            c.excite(es, at: t, clicks: cl)
        }
        func typebar(_ c: inout Canvas, at t0: Double) {
            let tb = c.body(Machine.typebar, spread: 0.025)
            let lk = c.body(Machine.linkage, spread: 0.05)
            let fr = c.body(Machine.frame, spread: 0.008)
            c.excite(lk, at: t0, clicks: [(0, 0.09)])
            let hit = t0 + 0.006 + c.rng.uni() * 0.004
            let b1 = 0.0005 + c.rng.uni() * 0.0005
            c.excite(tb, at: hit, clicks: [(0, 1.0), (b1, 0.40), (b1 * 2.7, 0.14)])
            c.excite(fr, at: hit, clicks: [(0, 0.015)])
            c.thud(at: hit, amp: 0.95, cutoff: 240, tau: 0.010)
        }
        func lever(_ c: inout Canvas, at t: Double, amp: Double) {
            let hs = c.body(Machine.housing, spread: 0.03)
            c.excite(hs, at: t, clicks: [(0, amp), (0.0011, amp * 0.4)], width: 0.0003)
            c.thud(at: t, amp: amp * 1.1, cutoff: 280, tau: 0.012)
        }
        func bang(_ c: inout Canvas, at t: Double, amp: Double) {
            let cb = c.body(Machine.carriage, spread: 0.015)
            let fr = c.body(Machine.frame, spread: 0.008)
            c.excite(cb, at: t, clicks: [(0, amp), (0.0013, amp * 0.5), (0.0041, amp * 0.22)], width: 0.00025)
            c.excite(fr, at: t, clicks: [(0, amp * 0.13)])
            c.thud(at: t, amp: amp * 1.4, cutoff: 200, tau: 0.022)
        }

        switch s {
        case .key:
            press(&c, Machine.keyboard, cav: 560, weight: 0.85)
            return c.finish(peak: 0.85)
        case .keyUp:
            release(&c, Machine.keyboard, cav: 560, weight: 0.5)
            return c.finish(peak: 0.30)
        case .wide:
            press(&c, Machine.longKey, cav: 420, weight: 1.0, stab: true)
            return c.finish(peak: 0.85)
        case .wideUp:
            release(&c, Machine.longKey, cav: 420, weight: 0.6)
            return c.finish(peak: 0.32)
        case .space:
            press(&c, Machine.longKey, cav: 340, weight: 1.0, stab: true)
            return c.finish(peak: 0.85)
        case .spaceUp:
            release(&c, Machine.longKey, cav: 300, weight: 0.7)
            return c.finish(peak: 0.34)

        case .toHangul, .toEnglish:
            // 묵직한 키 하나 '도각' + 작은 종 두 음이 올라가거나(한) 내려간다(영)
            c = Canvas(seconds: 1.0, seed: seed)
            press(&c, Machine.longKey, cav: 380, weight: 1.0, stab: true)
            let lo = 1568.0, hi = 2093.0   // G6, C7
            let (a, b) = s == .toHangul ? (lo, hi) : (hi, lo)
            c.bell(at: 0.045, f: a, amp: 0.30, decay: 0.45)
            c.bell(at: 0.120, f: b, amp: 0.36, decay: 0.55)
            return c.finish(peak: 0.40)

        case .bell:
            c = Canvas(seconds: 1.4, seed: seed)
            c.bell(at: 0.002, f: 2050, amp: 0.8, decay: 0.7)
            return c.finish(peak: 0.32)

        case .typeClick:
            typebar(&c, at: 0)
            return c.finish(peak: 0.80)
        case .typeRelease:
            escapement(&c, at: 0.001, amp: 0.6)
            return c.finish(peak: 0.30)
        case .typeRight:
            let lk = c.body(Machine.linkage, spread: 0.05)
            c.excite(lk, at: 0, clicks: [(0, 0.12)])
            lever(&c, at: 0.005 + c.rng.uni() * 0.003, amp: 0.55)
            escapement(&c, at: 0.026 + c.rng.uni() * 0.01, amp: 0.40)
            return c.finish(peak: 0.72)
        case .scrollTick:
            escapement(&c, at: 0.0005, amp: 0.5, clicks: 1)
            return c.finish(peak: 0.16)
        case .dragTick:
            // 캐리지 랙 한 칸: 이스케이프먼트 이빨이 '틱' 넘어가고 캐리지 몸통이 살짝 울린다. 스크롤 틱보다 낮고 부드럽게.
            let es = c.body(Machine.escape, spread: 0.04)
            let cb = c.body(Machine.carriage, spread: 0.02)
            c.slide(at: 0, dur: 0.022, rise: 0.004, fall: 0.012, lo: 900, hi: 3800, amp: 0.05)
            c.excite(es, at: 0.003 + c.rng.uni() * 0.002, clicks: [(0, 0.32)], width: 0.00022)
            c.excite(cb, at: 0.003, clicks: [(0, 0.10)], width: 0.0003)
            c.thud(at: 0.003, amp: 0.18, cutoff: 260, tau: 0.008)
            return c.finish(peak: 0.13)

        case .carriage:
            c = Canvas(seconds: 0.8, seed: seed)
            lever(&c, at: 0, amp: 0.45)
            escapement(&c, at: 0.030, amp: 0.55, clicks: 1)
            escapement(&c, at: 0.052, amp: 0.48, clicks: 1)
            let s0 = 0.068, len = 0.29 + c.rng.uni() * 0.04
            let es = c.body(Machine.escape, spread: 0.02)
            c.slide(at: s0, dur: len, rise: 0.03, fall: 0.05, lo: 1100, hi: 4800, amp: 0.055)
            var t = s0 + 0.008
            while t < s0 + len - 0.012 {
                let prog = (t - s0) / len
                c.excite(es, at: t, clicks: [(0, 0.10 * sin(.pi * min(1, prog * 1.15)) * c.rng.jit(0.25))])
                t += 1 / (170 * (0.8 + 0.4 * sin(.pi * prog))) * c.rng.jit(0.12)
            }
            bang(&c, at: s0 + len, amp: 1.0)
            return c.finish(peak: 0.85)
        }
    }
}
