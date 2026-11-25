import AppKit

// 디버그: Tajagi --render <폴더>  → 모든 소리를 WAV로 저장하고 종료
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    do { try AudioOut.renderWavs(to: URL(fileURLWithPath: args[i + 1])); exit(0) } catch { print(error); exit(1) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
