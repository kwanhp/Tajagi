import AVFoundation
import AppKit
import CoreAudio
import QuartzCore

/// 미리 렌더링한 버퍼를 여러 보이스(AVAudioPlayerNode)로 겹쳐 재생한다.
final class AudioOut {
    private var engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 1)!
    private var nodes: [AVAudioPlayerNode] = []
    private var busyUntil: [CFTimeInterval] = []
    private var cursor = 0
    private var buffers: [Sound: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [Sound: Int] = [:]
    private let voices: Int
    private var configObserver: NSObjectProtocol?
    private var rebuildPending = false

    private var comp: AVAudioUnitEffect?

    var master: Float = 0.6 { didSet { engine.mainMixerNode.outputVolume = master } }
    /// 부스트 단계 0…4 (끔·약·중·강·최강). 시스템 볼륨(=노래 볼륨)은 그대로 두고 타자 소리만 크게 만드는 용도.
    /// 소리가 이미 0 dBFS 가까이 나가서 그냥 키우면 찢어지므로
    ///  - 약·중·강: 컴프레서가 '딸깍' 머리는 누르고 꼬리·몸통을 끌어올린다(6/12/18 dB)
    ///  - 강·최강: 소리 하나하나를 tanh로 살짝/더 포화시켜 파형을 꽉 채운다(+8 kHz 로우패스로 거친 고역은 깎음)
    ///  - 마지막 피크 리미터가 0 dBFS를 넘지 않게 막는다
    /// 실측(오프라인 렌더, 50 ms 창 RMS, 끔 대비): 키 소리 강 +8 dB, 최강 +11 dB / 클릭 +10 dB / 스페이스 +10~12 dB
    var boostLevel: Int = 0 { didSet { applyBoost() } }
    private static let compDB: [Float] = [0, 6, 12, 18, 18]
    private static let satK: [Float] = [0, 0, 0, 2, 4]
    private var raw: [Sound: [[Float]]] = [:]
    private var bufferSat: Float = -1

    private func applyBoost() {
        let lv = max(0, min(4, boostLevel))
        let k = Self.satK[lv]
        if k != bufferSat { makeBuffers(sat: k) }
        guard let c = comp else { return }
        let b = Self.compDB[lv]
        c.bypass = b < 0.5
        let u = c.audioUnit
        func set(_ p: AudioUnitParameterID, _ v: Float) { AudioUnitSetParameter(u, p, kAudioUnitScope_Global, 0, v, 0) }
        set(kDynamicsProcessorParam_Threshold, -b)
        set(kDynamicsProcessorParam_HeadRoom, 1.5)
        set(kDynamicsProcessorParam_AttackTime, 0.0005)
        set(kDynamicsProcessorParam_ReleaseTime, 0.05)
        set(kDynamicsProcessorParam_OverallGain, b)
    }

    /// 미리 렌더링한 소리로 재생 버퍼를 만든다. sat > 0이면 소리마다 tanh 포화 + 8 kHz 로우패스 후 원래 피크로 맞춘다.
    private func makeBuffers(sat k: Float) {
        bufferSat = k
        var out: [Sound: [AVAudioPCMBuffer]] = [:]
        for (s, vs) in raw {
            out[s] = vs.map { orig in
                var x = orig
                if k > 0, let pk = x.map(abs).max(), pk > 0 {
                    let g = k / pk, norm = tanh(k)
                    for i in x.indices { x[i] = tanh(g * x[i]) / norm * pk }
                    var lp = Biquad.lowpass(8000)
                    for i in x.indices { x[i] = Float(lp.run(Double(x[i]))) }
                    if let p2 = x.map(abs).max(), p2 > 0 { let r = pk / p2; for i in x.indices { x[i] *= r } }
                }
                let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(x.count))!
                b.frameLength = AVAudioFrameCount(x.count)
                x.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
                return b
            }
        }
        buffers = out
    }

    init(voices: Int = 24) {
        self.voices = voices
        raw = SoundBank.renderAll()
        makeBuffers(sat: 0)
        build()
        // 기본 출력 장치가 바뀌면(에어팟 연결·해제 등) 엔진을 통째로 새로 만든다.
        // AVAudioEngine은 멈췄다 다시 켜도 예전 장치에 붙어 있는 경우가 있어서 stop/start만으로는 부족하다.
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.scheduleRebuild()
        }
        // 잠자기에서 깨어나면 블루투스 출력이 끊겨 있는 경우가 있어 새로 만든다
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }
    }

    /// 장치 전환 직후엔 알림이 여러 번 오고 장치가 아직 준비 안 됐을 수 있어 잠깐 모았다가 한 번만 새로 만든다
    private func scheduleRebuild() {
        if rebuildPending { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            self.build()
        }
    }

    private func build() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        engine.stop()
        for n in nodes { n.stop(); engine.detach(n) }
        engine = AVAudioEngine()
        nodes = []; busyUntil = []; cursor = 0
        for _ in 0..<voices {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            nodes.append(n)
            busyUntil.append(0)
        }
        engine.mainMixerNode.outputVolume = master
        // mainMixer → 컴프레서(부스트) → 피크 리미터 → 출력
        func fx(_ t: OSType) -> AVAudioUnitEffect {
            AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect, componentSubType: t,
                componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        }
        let c = fx(kAudioUnitSubType_DynamicsProcessor), lim = fx(kAudioUnitSubType_PeakLimiter)
        engine.attach(c); engine.attach(lim)
        let hw = engine.outputNode.outputFormat(forBus: 0)
        let mixFmt = AVAudioFormat(standardFormatWithSampleRate: hw.sampleRate > 0 ? hw.sampleRate : SR, channels: 2)!
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: c, format: mixFmt)
        engine.connect(c, to: lim, format: mixFmt)
        engine.connect(lim, to: engine.outputNode, format: mixFmt)
        comp = c
        applyBoost()
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }
        start()
    }

    private func start() {
        do { try engine.start() } catch { NSLog("Tajagi audio start failed: \(error)") ; return }
        for n in nodes { n.play() }
        busyUntil = busyUntil.map { _ in 0 }
    }

    /// gain 0…1, pan -1…1
    func play(_ s: Sound, gain: Float = 1, pan: Float = 0) {
        guard let vs = buffers[s], !vs.isEmpty else { return }
        if !engine.isRunning { start() }
        // 직전과 같은 변형은 피한다
        var v = Int.random(in: 0..<vs.count)
        if vs.count > 1, v == lastVariant[s] { v = (v + 1) % vs.count }
        lastVariant[s] = v
        let buf = vs[v]

        // 비어 있는 보이스를 고르고, 없으면 가장 먼저 끝나는 보이스를 끊고 쓴다
        let now = CACurrentMediaTime()
        var pick = -1
        for k in 0..<nodes.count {
            let i = (cursor + k) % nodes.count
            if busyUntil[i] <= now { pick = i; break }
        }
        if pick < 0 { pick = busyUntil.indices.min { busyUntil[$0] < busyUntil[$1] }! }
        cursor = (pick + 1) % nodes.count

        let n = nodes[pick]
        n.volume = max(0, min(1, gain))
        n.pan = max(-1, min(1, pan))
        n.scheduleBuffer(buf, at: nil, options: .interrupts)
        busyUntil[pick] = now + Double(buf.frameLength) / SR + 0.01
    }

    /// 디버그: 모든 소리를 WAV로 저장
    static func renderWavs(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 1)!
        for (s, vs) in SoundBank.renderAll() {
            for (i, samples) in vs.prefix(2).enumerated() {
                let url = dir.appendingPathComponent("\(s.rawValue)-\(i).wav")
                let f = try AVAudioFile(forWriting: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: SR, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                ])
                let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))!
                b.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                try f.write(from: b)
            }
        }
    }
}
