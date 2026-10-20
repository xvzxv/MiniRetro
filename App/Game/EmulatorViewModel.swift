// EmulatorViewModel.swift — 游戏会话驱动中枢（M1-M4）
// 持有 RetroCore（ObjC 桥接）+ RetroAudioEngine，串联输入/存档/金手指/快进/后台策略
import AVFoundation
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class EmulatorViewModel: ObservableObject {
    // MARK: - 发布状态

    @Published var isPaused = false
    @Published var isFastForwarding = false
    @Published var statusMessage: String?
    @Published var measuredFPS: Double = 0
    @Published var audioLatencyMs: Double = 0
    @Published private(set) var isLoaded = false

    let retroCore: RetroCore
    private let audioEngine: RetroAudioEngine
    private(set) var rom: ROMEntry
    private(set) var cheats: CheatManager

    private var renderer: EmulatorRenderer?
    private var fpsTimer: Timer?
    private var wasPausedByBackground = false

    var onRequestMenu: (() -> Void)?

    /// 退出游戏回调（由 GameView 设置 → dismiss）
    var exitGame: (() -> Void)?

    // MARK: - 目录

    private var savesDirectory: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(rom.id.uuidString, isDirectory: true)
    }

    private var thumbnailsDirectory: URL {
        savesDirectory.appendingPathComponent("thumbs", isDirectory: true)
    }

    // MARK: - 初始化

    init(rom: ROMEntry) {
        self.rom = rom
        retroCore = RetroCore(coreNamed: rom.system.coreName)
        audioEngine = RetroAudioEngine(ringBuffer: retroCore.audioRingBuffer)
        cheats = CheatManager(romID: rom.id, retroCore: retroCore)
        observeLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 加载

    func attachRenderer(_ renderer: EmulatorRenderer) {
        self.renderer = renderer
    }

    func loadROM() {
        let romsDir = FileManager.default.documentsDirectory
            .appendingPathComponent("ROMs", isDirectory: true)
        let romURL = romsDir.appendingPathComponent(rom.relativePath)
        FileManager.default.ensureDirectory(savesDirectory)

        retroCore.setSystemDirectory(FileManager.default.documentsDirectory.path)
        retroCore.setSaveDirectory(savesDirectory.path)

        do {
            try retroCore.loadROM(atPath: romURL.path)
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
            MRLog.error("ROM 加载失败: \(error.localizedDescription)")
            return
        }
        retroCore.start()
        audioEngine.start(sampleRate: Double(retroCore.audioSampleRate), volume: SettingsStore.shared.volume)
        isLoaded = true
        startFPSMonitor()
        MRLog.info("ROM 已加载: \(rom.fileName) core=\(rom.system.coreName) size=\(retroCore.videoBaseSize)")
    }

    func unload() {
        stopFPSMonitor()
        audioEngine.stop()
        retroCore.flushBatterySave()
        retroCore.stop()
        retroCore.unloadROM()
        isLoaded = false
    }

    // MARK: - 运行控制

    func pause() {
        retroCore.pause()
        isPaused = true
    }

    func resume() {
        retroCore.resume()
        isPaused = false
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func resetGame() {
        retroCore.reset()
    }

    func setFastForward(_ enabled: Bool) {
        retroCore.setFastForward(enabled: enabled, multiplier: SettingsStore.shared.fastForwardMultiplier)
        isFastForwarding = enabled
    }

    // MARK: - 输入

    func setButton(_ button: JoypadButton, pressed: Bool, port: Int = 0) {
        retroCore.setButton(UInt(button.rawValue), pressed: pressed, forPort: UInt(port))
    }

    // MARK: - 即时存档（多槽位 + 缩略图）

    private func stateURL(slot: Int, auto: Bool) -> URL {
        savesDirectory.appendingPathComponent(auto ? "auto.mrstate" : "slot-\(slot).mrstate")
    }

    private func thumbnailURL(slot: Int, auto: Bool) -> URL {
        thumbnailsDirectory.appendingPathComponent(auto ? "auto.png" : "slot-\(slot).png")
    }

    /// 保存即时存档；返回错误信息或 nil
    @discardableResult
    func saveState(slot: Int, auto: Bool = false) -> String? {
        guard retroCore.serializeSize > 0 else { return "当前核心不支持即时存档" }
        guard let data = retroCore.serializeState() else { return "序列化失败" }
        FileManager.default.ensureDirectory(savesDirectory)
        do {
            try data.write(to: stateURL(slot: slot, auto: auto), options: .atomic)
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
        if let image = captureThumbnail() {
            FileManager.default.ensureDirectory(thumbnailsDirectory)
            if let png = image.pngDataCompat() {
                try? png.write(to: thumbnailURL(slot: slot, auto: auto), options: .atomic)
            }
        }
        Haptics.success()
        MRLog.info("即时存档 slot=\(slot) auto=\(auto) bytes=\(data.count)")
        return nil
    }

    @discardableResult
    func loadState(slot: Int, auto: Bool = false) -> String? {
        let url = stateURL(slot: slot, auto: auto)
        guard let data = try? Data(contentsOf: url) else { return "存档不存在" }
        if !retroCore.unserializeState(data) {
            return "读档失败（存档可能不兼容）"
        }
        Haptics.success()
        MRLog.info("即时读档 slot=\(slot) auto=\(auto)")
        return nil
    }

    func deleteState(slot: Int, auto: Bool = false) {
        try? FileManager.default.removeItem(at: stateURL(slot: slot, auto: auto))
        try? FileManager.default.removeItem(at: thumbnailURL(slot: slot, auto: auto))
    }

    /// 扫描已有槽位（供 UI 展示缩略图）
    func existingStates() -> [SaveStateEntry] {
        let fm = FileManager.default
        var result: [SaveStateEntry] = []
        for slot in 1...4 {
            let url = stateURL(slot: slot, auto: false)
            if fm.fileExists(atPath: url.path),
               let attrs = try? fm.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                let hasThumb = fm.fileExists(atPath: thumbnailURL(slot: slot, auto: false).path)
                result.append(SaveStateEntry(slot: slot, timestamp: date, thumbnailName: hasThumb ? "slot-\(slot)" : nil))
            }
        }
        let autoURL = stateURL(slot: 0, auto: true)
        if fm.fileExists(atPath: autoURL.path) {
            result.append(SaveStateEntry(slot: 0, timestamp: Date(), isAutoSave: true))
        }
        return result
    }

    func thumbnailImage(for entry: SaveStateEntry) -> CrossImage? {
        guard let name = entry.thumbnailName else { return nil }
        let url = thumbnailsDirectory.appendingPathComponent("\(name).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return CrossImage(data: data)
    }

    /// 从当前帧捕获缩略图（主线程调用）
    func captureThumbnail() -> CrossImage? {
        let maxPixels = 512 * 512 * 4
        var buffer = [UInt8](repeating: 0, count: maxPixels)
        var width: Int = 0
        var height: Int = 0
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return retroCore.copyCurrentFrame(toBuffer: base, width: &width, height: &height)
        }
        guard ok, width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(bytes: buffer, count: bytesPerRow * height) as CFData) else {
            return nil
        }
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        return cgImage.map { CrossImage.fromCGImage($0) }
    }

    // MARK: - 正常存档（电池）

    func flushBatterySave() {
        retroCore.flushBatterySave()
    }

    // MARK: - 后台策略（进后台暂停 + 自动即时存档，可配置）

    private func observeLifecycle() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleBackground),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        #endif
    }

    @objc private func handleBackground() {
        guard isLoaded else { return }
        if SettingsStore.shared.autoPauseOnBackground {
            wasPausedByBackground = !isPaused
            pause()
        }
        if SettingsStore.shared.autoSaveOnBackground {
            saveState(slot: 0, auto: true)
        }
        flushBatterySave()
        MRLog.info("进入后台：已暂停 + 自动存档")
    }

    @objc private func handleForeground() {
        guard isLoaded else { return }
        if wasPausedByBackground {
            wasPausedByBackground = false
            resume()
        }
    }

    // MARK: - FPS 监控

    private func startFPSMonitor() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.measuredFPS = self.renderer?.measuredFPS ?? 0
                self.audioLatencyMs = self.audioEngine.estimatedLatencyMs()
            }
        }
    }

    private func stopFPSMonitor() {
        fpsTimer?.invalidate()
        fpsTimer = nil
    }
}
