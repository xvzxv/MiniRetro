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

    // 连发（turbo）状态
    private var directHeld: Set<JoypadButton> = []   // 直接按下的普通键
    private var turboHeld: Set<JoypadButton> = []    // 正被按住的连发键（.turboA/.turboB）
    private var turboTimer: Timer?
    private var turboPhase = false                   // 连发相位（true 时目标键按下）

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
        NSLog("[MiniRetro] loadOK file=%@ system=%@ geometry=%.0fx%.0f audio=%ld",
              rom.fileName, rom.system.rawValue,
              retroCore.videoBaseSize.width, retroCore.videoBaseSize.height,
              Int(retroCore.audioSampleRate))

        // 自动载入上次的自动存档（可在设置中关闭）
        if SettingsStore.shared.autoLoadOnStart,
           FileManager.default.fileExists(atPath: stateURL(slot: 0, auto: true).path) {
            if let error = loadState(slot: 0, auto: true) {
                NSLog("[MiniRetro] 自动读档失败: %@", error)
            } else {
                NSLog("[MiniRetro] 已自动载入自动存档")
                statusMessage = "已载入上次进度"
            }
        }
    }

    func unload() {
        // 退出前存一次自动存档，保证下次进入能续上
        if isLoaded, SettingsStore.shared.autoSaveOnBackground {
            saveState(slot: 0, auto: true)
        }
        releaseAllInputs()
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

    /// 按键事件入口（虚拟按键 / 蓝牙手柄共用）
    /// 连发键（turboA/turboB）由本层拦截，不下发 core；
    /// 它们通过定时翻转相位，驱动对应的 A/B 状态。
    func setButton(_ button: JoypadButton, pressed: Bool, port: Int = 0) {
        if button.isTurbo {
            if pressed {
                turboHeld.insert(button)
            } else {
                turboHeld.remove(button)
            }
            updateTurboTimer()
            refreshInputs(port: port)
            return
        }
        if pressed {
            directHeld.insert(button)
        } else {
            directHeld.remove(button)
        }
        refreshInputs(port: port)
    }

    /// 根据「直接按下 + 连发相位」计算最终按键状态并下发
    private func refreshInputs(port: Int = 0) {
        for button in JoypadButton.allCases where !button.isTurbo {
            let pressed = directHeld.contains(button) || turboActive(for: button)
            retroCore.setButton(UInt(button.rawValue), pressed: pressed, forPort: UInt(port))
        }
    }

    /// 该键此刻是否应因连发而按下
    private func turboActive(for button: JoypadButton) -> Bool {
        guard turboPhase else { return false }
        switch button {
        case .a: return turboHeld.contains(.turboA)
        case .b: return turboHeld.contains(.turboB)
        default: return false
        }
    }

    /// 有连发键按住时启动翻转定时器，全部松开则停止并复位
    private func updateTurboTimer() {
        turboTimer?.invalidate()
        turboTimer = nil
        guard !turboHeld.isEmpty else {
            turboPhase = false
            return
        }
        let rate = max(1, SettingsStore.shared.turboRate)   // 每秒完整周期数
        let interval = 1.0 / Double(rate * 2)               // 半周期翻转
        turboTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.turboPhase.toggle()
            self.refreshInputs()
        }
    }

    /// 清空所有按键状态（暂停/退出时避免卡键）
    private func releaseAllInputs() {
        directHeld.removeAll()
        turboHeld.removeAll()
        turboPhase = false
        turboTimer?.invalidate()
        turboTimer = nil
        for button in JoypadButton.allCases where !button.isTurbo {
            retroCore.setButton(UInt(button.rawValue), pressed: false, forPort: 0)
        }
    }

    // MARK: - 即时存档（自动槽 + 手动槽 + 缩略图）

    /// 手动槽位数量（自动存档单独一个槽）
    static let manualSlotCount = 3

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

    /// 固定的槽位列表：1 个自动存档槽 + N 个手动槽。
    /// 空槽也会返回（isOccupied = false），让菜单展示完整的槽位结构。
    func saveSlots() -> [SaveStateEntry] {
        var result: [SaveStateEntry] = [makeEntry(slot: 0, auto: true)]
        for slot in 1...Self.manualSlotCount {
            result.append(makeEntry(slot: slot, auto: false))
        }
        return result
    }

    private func makeEntry(slot: Int, auto: Bool) -> SaveStateEntry {
        let fm = FileManager.default
        let stateFile = stateURL(slot: slot, auto: auto)
        var entry = SaveStateEntry(
            slot: slot,
            timestamp: .distantPast,
            thumbnailName: nil,
            isAutoSave: auto,
            isOccupied: false
        )
        guard let attrs = try? fm.attributesOfItem(atPath: stateFile.path),
              let date = attrs[.modificationDate] as? Date else {
            return entry
        }
        entry.isOccupied = true
        entry.timestamp = date
        if fm.fileExists(atPath: thumbnailURL(slot: slot, auto: auto).path) {
            entry.thumbnailName = auto ? "auto" : "slot-\(slot)"
        }
        return entry
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
