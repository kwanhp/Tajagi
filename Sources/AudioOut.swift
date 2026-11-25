import AVFoundation
import QuartzCore

/// 미리 렌더링한 버퍼를 여러 보이스(AVAudioPlayerNode)로 겹쳐 재생한다.
final class AudioOut {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 1)!
    private var nodes: [AVAudioPlayerNode] = []
    private var busyUntil: [CFTimeInterval] = []
    private var cursor = 0
    private var buffers: [Sound: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [Sound: Int] = [:]

    var master: Float = 0.6 { didSet { engine.mainMixerNode.outputVolume = master } }

    init(voices: Int = 24) {
        for (s, vs) in SoundBank.renderAll() {
            buffers[s] = vs.map { samples in
                let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
                b.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { src in
                    b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
                }
                return b
            }
        }
        for _ in 0..<voices {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            nodes.append(n)
            busyUntil.append(0)
        }
        engine.mainMixerNode.outputVolume = master
        // 출력 장치가 바뀌면(이어폰 연결 등) 엔진이 멈추므로 다시 시작
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.start()
        }
        start()
    }

    private func start() {
        engine.stop()
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
