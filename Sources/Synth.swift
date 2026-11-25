import Foundation

// 타자기 소리 합성기.
// 녹음 샘플 없이 물리적 구성요소(충격 과도음, 감쇠 모드, 고무 플래튼의 저음 '쿵', 이스케이프먼트 딸깍,
// 캐리지 래칫, 벨)를 더해서 만든다. 앱 시작 시 한 번 렌더링해 메모리에 둔다.

let SR: Double = 48_000

/// 재현 가능한 난수(xorshift64*)
struct RNG {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        s ^= s >> 12; s ^= s << 25; s ^= s >> 27
        return s &* 2_685_821_657_736_338_717
    }
    /// [0, 1)
    mutating func uni() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// [-1, 1)
    mutating func bi() -> Double { uni() * 2 - 1 }
    /// 1 ± spread
    mutating func jit(_ spread: Double) -> Double { 1 + bi() * spread }
}

/// RBJ 쿡북 biquad
struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = 0.0, z2 = 0.0

    static func lowpass(_ f: Double, q: Double = 0.707) -> Biquad { make(f, q, kind: 0) }
    static func highpass(_ f: Double, q: Double = 0.707) -> Biquad { make(f, q, kind: 1) }
    static func bandpass(_ f: Double, q: Double) -> Biquad { make(f, q, kind: 2) }

    private static func make(_ f: Double, _ q: Double, kind: Int) -> Biquad {
        let w = 2 * Double.pi * min(f, SR * 0.45) / SR
        let cw = cos(w), alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        var bq = Biquad()
        if kind == 0 {
            bq.b0 = (1 - cw) / 2 / a0; bq.b1 = (1 - cw) / a0; bq.b2 = bq.b0
        } else if kind == 1 {
            bq.b0 = (1 + cw) / 2 / a0; bq.b1 = -(1 + cw) / a0; bq.b2 = bq.b0
        } else {
            bq.b0 = alpha / a0; bq.b1 = 0; bq.b2 = -alpha / a0
        }
        bq.a1 = -2 * cw / a0; bq.a2 = (1 - alpha) / a0
        return bq
    }

    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// 소리 한 개를 그리는 캔버스
struct Canvas {
    var x: [Double]
    var rng: RNG

    init(seconds: Double, seed: UInt64) {
        x = [Double](repeating: 0, count: Int(seconds * SR))
        rng = RNG(seed)
    }

    /// 감쇠 사인(공진 모드). 피치가 살짝 떨어지는 'drop'을 주면 둔탁한 타격감이 생긴다.
    mutating func mode(at t0: Double, f: Double, tau: Double, amp: Double, drop: Double = 0, attack: Double = 0) {
        let start = Int(t0 * SR)
        let n = min(x.count - start, Int(tau * 7 * SR))
        guard n > 0 else { return }
        var phase = rng.uni() * 0.3
        for i in 0..<n {
            let t = Double(i) / SR
            let fi = f * (1 + drop * exp(-t / 0.004))
            phase += fi / SR
            var env = exp(-t / tau)
            if attack > 0 { env *= 1 - exp(-t / attack) }
            x[start + i] += amp * env * sin(2 * .pi * phase)
        }
    }

    /// 대역 제한 잡음 버스트(충격 과도음, 마찰음)
    mutating func noise(at t0: Double, dur: Double, tau: Double, lo: Double, hi: Double, amp: Double, attack: Double = 0.0002) {
        let start = Int(t0 * SR)
        let n = min(x.count - start, Int(dur * SR))
        guard n > 0 else { return }
        var hp1 = Biquad.highpass(lo), hp2 = Biquad.highpass(lo)
        var lp1 = Biquad.lowpass(hi), lp2 = Biquad.lowpass(hi)
        for i in 0..<n {
            let t = Double(i) / SR
            let env = (1 - exp(-t / attack)) * exp(-t / tau) * min(1, Double(n - i) / (0.0005 * SR))
            let v = lp2.run(lp1.run(hp2.run(hp1.run(rng.bi()))))
            x[start + i] += amp * env * v
        }
    }

    /// 지속 잡음(캐리지 미끄러짐) — 사다리꼴 포락선
    mutating func slide(at t0: Double, dur: Double, rise: Double, fall: Double, lo: Double, hi: Double, amp: Double) {
        let start = Int(t0 * SR)
        let n = min(x.count - start, Int(dur * SR))
        guard n > 0 else { return }
        var hp = Biquad.highpass(lo), lp1 = Biquad.lowpass(hi), lp2 = Biquad.lowpass(hi)
        for i in 0..<n {
            let t = Double(i) / SR
            let env = min(1, t / rise) * min(1, (dur - t) / fall)
            x[start + i] += amp * env * lp2.run(lp1.run(hp.run(rng.bi())))
        }
    }

    /// 작은 종(타자기 여백 벨). 비조화 배음 + 살짝 어긋난 쌍으로 맥놀이.
    mutating func bell(at t0: Double, f: Double, amp: Double, decay: Double) {
        let partials: [(Double, Double, Double)] = [   // (배율, 세기, 감쇠 배율)
            (1.000, 1.00, 1.00), (1.0035, 0.55, 0.85), (2.756, 0.38, 0.40),
            (5.404, 0.16, 0.18), (8.933, 0.06, 0.08),
        ]
        for (r, a, d) in partials {
            mode(at: t0, f: f * r, tau: decay * d, amp: amp * a, attack: 0.0004)
        }
        noise(at: t0, dur: 0.004, tau: 0.0008, lo: 2500, hi: 9000, amp: amp * 0.5)
    }

    // MARK: 기계 몸체(공진체) — 타자기 소리의 정체
    // 진짜 타자기 소리는 깨끗한 음 몇 개가 아니라, 얇은 금속판·활자대·링키지가 동시에 울리는
    // '촘촘한 비조화 공진' + 음정 없는 둔탁한 쿵이다. 드럼처럼 들리지 않게 피치가 떨어지는 사인은 쓰지 않는다.

    /// 몸체 임펄스 응답 생성. 주파수 배치는 spec.seed(같은 기계)로 고정, 변형마다 ±spread 만큼만 흔든다.
    mutating func body(_ s: BodySpec, spread: Double = 0.02) -> [Double] {
        var r = RNG(s.seed)
        var ir = [Double](repeating: 0, count: Int(s.len * SR))
        for _ in 0..<s.n {
            let u = r.uni()
            let f0 = s.fLo * pow(s.fHi / s.fLo, u)
            let f = f0 * rng.jit(spread)
            let tau = min(s.tauLo * pow(s.tauHi / s.tauLo, u) * r.jit(0.35), s.maxCycles / f0)  // 흡음재: 오래 울리는 저음 모드 억제
            let a = (0.45 + 0.55 * r.uni()) * pow(f0 / s.fLo, -s.tilt)
            let ph = r.uni() * 2 * .pi
            let n = min(ir.count, Int(tau * 7 * SR))
            let w = 2 * Double.pi * f / SR
            for i in 0..<n { ir[i] += a * exp(-Double(i) / (tau * SR)) * sin(w * Double(i) + ph) }
        }
        if let t = s.tail {   // 덜걱거림(잔떨림) — 확산 잡음 꼬리
            var hp = Biquad.highpass(t.lo), lp = Biquad.lowpass(t.hi)
            let m = ir.map { abs($0) }.max() ?? 1
            for i in 0..<ir.count {
                ir[i] += t.amp * m * exp(-Double(i) / (t.tau * SR)) * lp.run(hp.run(rng.bi())) * 2
            }
        }
        // 시작 0.15 ms 페이드인(위상 랜덤 때문에 생기는 계단 방지) + 피크 1로 정규화
        let fi = Int(0.00015 * SR)
        for i in 0..<min(fi, ir.count) { ir[i] *= Double(i) / Double(fi) }
        let m = ir.map { abs($0) }.max() ?? 1
        return ir.map { $0 / m }
    }

    /// 짧은 충격(clicks: 시간차, 세기)으로 몸체를 때린다 = 충격 × 임펄스 응답의 합성곱
    mutating func excite(_ ir: [Double], at t0: Double, clicks: [(Double, Double)], width: Double = 0.00010) {
        let w = max(1, Int(width * SR))
        for (dt, a) in clicks {
            let start = Int((t0 + dt) * SR)
            guard start >= 0, start < x.count else { continue }
            for j in 0..<w {
                let e = a * (j == 0 ? 1 : rng.bi() * 0.6) * (1 - Double(j) / Double(w + 1))
                let base = start + j
                guard base < x.count else { break }
                let n = min(ir.count, x.count - base)
                for k in 0..<n { x[base + k] += e * ir[k] }
            }
        }
    }

    /// 넓은 공명(키캡 속 빈 공간의 '도각') — 공명 대역 통과 잡음. Q가 낮아서 음정으로 들리지 않는다.
    mutating func cavity(at t0: Double, f: Double, q: Double, tau: Double, amp: Double, attack: Double = 0.0004) {
        let start = Int(t0 * SR)
        let n = min(x.count - start, Int(tau * 7 * SR))
        guard n > 0 else { return }
        var b1 = Biquad.bandpass(f, q: q), b2 = Biquad.bandpass(f, q: q)
        var buf = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / SR
            buf[i] = b2.run(b1.run(rng.bi() * (1 - exp(-t / attack)) * exp(-t / tau)))
        }
        let m = buf.map { abs($0) }.max() ?? 1
        for i in 0..<n { x[start + i] += amp * buf[i] / m }
    }

    /// 음정 없는 둔탁한 '쿵'(고무 플래튼·책상) — 저역 통과 잡음
    mutating func thud(at t0: Double, amp: Double, cutoff: Double, tau: Double, attack: Double = 0.0006) {
        let start = Int(t0 * SR)
        let n = min(x.count - start, Int(tau * 7 * SR))
        guard n > 0 else { return }
        var hp = Biquad.highpass(45), lp1 = Biquad.lowpass(cutoff), lp2 = Biquad.lowpass(cutoff)
        var buf = [Double](repeating: 0, count: n)
        for i in 0..<n { buf[i] = lp2.run(lp1.run(hp.run(rng.bi()))) }
        let m = buf.map { abs($0) }.max() ?? 1
        for i in 0..<n {
            let t = Double(i) / SR
            x[start + i] += amp * buf[i] / m * (1 - exp(-t / attack)) * exp(-t / tau)
        }
    }

    // MARK: 마감

    /// 책상 위 초기 반사(아주 짧은 공간감) + 부드러운 포화 + 끝 페이드 + 피크 정규화
    mutating func finish(peak: Double) -> [Float] {
        let taps: [(Double, Double)] = [(0.0031, 0.16), (0.0074, 0.11), (0.0118, 0.07), (0.0193, 0.045)]
        let dry = x
        for (d, g) in taps {
            let k = Int(d * SR)
            var lp = Biquad.lowpass(3800)
            for i in k..<x.count { x[i] += g * lp.run(dry[i - k]) }
        }
        // 귀를 찌르는 초고역을 살짝 깎는다(감각 피로 방지)
        var shelf = Biquad.lowpass(9500, q: 0.6)
        for i in 0..<x.count { x[i] = shelf.run(x[i]) }

        let m = x.map { abs($0) }.max() ?? 1
        let g = m > 0 ? 1.0 / m : 1
        let fade = Int(0.006 * SR)
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            var v = tanh(1.4 * x[i] * g) / tanh(1.4)
            if i > x.count - fade { v *= Double(x.count - i) / Double(fade) }
            out[i] = Float(v * peak)
        }
        // 뒤쪽 무음 잘라내기
        var end = out.count
        while end > 1, abs(out[end - 1]) < 1e-4 { end -= 1 }
        return Array(out[0..<max(end, 1)])
    }
}

/// 공진체 규격. tauLo/tauHi = fLo/fHi 에서의 감쇠 시간. tilt = 고역으로 갈수록 약해지는 정도.
struct BodySpec {
    var n: Int, fLo: Double, fHi: Double, tauLo: Double, tauHi: Double, tilt: Double, len: Double, seed: UInt64
    var tail: (amp: Double, lo: Double, hi: Double, tau: Double)? = nil
    var maxCycles: Double = .infinity
}

/// 한 대의 타자기(고정 시드) — 모든 소리가 같은 기계에서 나도록
enum Machine {
    /// 활자대가 플래튼을 때릴 때 울리는 활자대+바구니+프레임: 밝고 촘촘한 금속성
    static let typebar = BodySpec(n: 44, fLo: 700, fHi: 8800, tauLo: 0.016, tauHi: 0.0022, tilt: 0.22, len: 0.07, seed: 11,
                                  tail: (0.22, 1600, 7500, 0.005))
    /// 휴대용 타자기 특유의 얇은 철판 '칭' 울림(아주 작게)
    static let frame = BodySpec(n: 9, fLo: 1900, fHi: 5600, tauLo: 0.085, tauHi: 0.045, tilt: 0, len: 0.30, seed: 12)
    /// 키 레버·링키지의 잔 딸깍
    static let linkage = BodySpec(n: 18, fLo: 1500, fHi: 9000, tauLo: 0.0045, tauHi: 0.0014, tilt: 0.1, len: 0.025, seed: 13)
    /// 이스케이프먼트·래칫 '틱'
    static let escape = BodySpec(n: 26, fLo: 2100, fHi: 9200, tauLo: 0.0045, tauHi: 0.0015, tilt: 0.12, len: 0.04, seed: 14)
    /// 본체 하우징(스페이스바·시프트·레버) — 중저역, 더 둔함
    static let housing = BodySpec(n: 40, fLo: 320, fHi: 4200, tauLo: 0.008, tauHi: 0.003, tilt: 0.12, len: 0.07, seed: 15,
                                  tail: (0.18, 400, 2600, 0.006))
    /// 캐리지가 끝에 부딪힐 때 — 크고 무거운 금속 덩어리
    static let carriage = BodySpec(n: 44, fLo: 340, fHi: 6800, tauLo: 0.026, tauHi: 0.004, tilt: 0.15, len: 0.22, seed: 16,
                                   tail: (0.28, 600, 5200, 0.012))
    /// 기계식 키보드: PBT 키캡 + 보강판 + 흡음재 넣은 케이스 — 중저역 위주, 금속 울림 없음
    static let keyboard = BodySpec(n: 56, fLo: 300, fHi: 6000, tauLo: 0.008, tauHi: 0.0012, tilt: 0.25, len: 0.06, seed: 21,
                                   tail: (0.10, 220, 1800, 0.004), maxCycles: 2.5)
    /// 스테빌라이저 달린 긴 키(스페이스·엔터·백스페이스·시프트) — 더 낮고 깊게
    static let longKey = BodySpec(n: 60, fLo: 240, fHi: 5000, tauLo: 0.011, tauHi: 0.0012, tilt: 0.32, len: 0.08, seed: 22,
                                  tail: (0.12, 140, 1400, 0.007), maxCycles: 2.5)
    /// 마우스 스위치(타자기와 별개, 작고 건조함)
    static let mouse = BodySpec(n: 24, fLo: 1100, fHi: 8000, tauLo: 0.0045, tauHi: 0.0015, tilt: 0.15, len: 0.02, seed: 17)
}
