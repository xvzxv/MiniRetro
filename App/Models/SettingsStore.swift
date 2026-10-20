// SettingsStore.swift — 全局设置（UserDefaults 持久化）
import Foundation

enum FilterMode: String, Codable, CaseIterable, Identifiable {
    case integer   // 整数倍像素（默认）
    case smooth    // 线性平滑
    case crt       // CRT 扫描线
    case lcd       // GB LCD 点阵

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .integer: return "像素（整数倍）"
        case .smooth: return "平滑"
        case .crt: return "CRT 扫描线"
        case .lcd: return "LCD 点阵"
        }
    }

    var metalShaderName: String {
        switch self {
        case .integer: return "video_filter_integer"
        case .smooth: return "video_filter_smooth"
        case .crt: return "video_filter_crt"
        case .lcd: return "video_filter_lcd"
        }
    }
}

enum SkinType: String, Codable, CaseIterable, Identifiable {
    case classic    // 经典红白机配色
    case minimal    // 透明极简

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典红白机"
        case .minimal: return "透明极简"
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // MARK: - 发布属性（didSet 落盘）

    @Published var fastForwardMultiplier: Int {
        didSet { defaults.set(fastForwardMultiplier, forKey: Keys.ffMultiplier) }
    }
    @Published var autoPauseOnBackground: Bool {
        didSet { defaults.set(autoPauseOnBackground, forKey: Keys.autoPause) }
    }
    /// 进后台自动即时存档（可配置）
    @Published var autoSaveOnBackground: Bool {
        didSet { defaults.set(autoSaveOnBackground, forKey: Keys.autoSave) }
    }
    @Published var filterMode: FilterMode {
        didSet { defaults.set(filterMode.rawValue, forKey: Keys.filter) }
    }
    @Published var volume: Float {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published var skin: SkinType {
        didSet { defaults.set(skin.rawValue, forKey: Keys.skin) }
    }
    @Published var showFPS: Bool {
        didSet { defaults.set(showFPS, forKey: Keys.showFPS) }
    }
    /// 低端机（iPad 6/A10）降级：关闭重滤镜、降低缓冲
    @Published var lowPerformanceMode: Bool {
        didSet { defaults.set(lowPerformanceMode, forKey: Keys.lowPerf) }
    }

    private enum Keys {
        static let ffMultiplier = "settings.ffMultiplier"
        static let autoPause = "settings.autoPause"
        static let autoSave = "settings.autoSave"
        static let filter = "settings.filter"
        static let volume = "settings.volume"
        static let haptics = "settings.haptics"
        static let skin = "settings.skin"
        static let showFPS = "settings.showFPS"
        static let lowPerf = "settings.lowPerformanceMode"
    }

    private init() {
        fastForwardMultiplier = defaults.object(forKey: Keys.ffMultiplier) as? Int ?? 2
        autoPauseOnBackground = defaults.object(forKey: Keys.autoPause) as? Bool ?? true
        autoSaveOnBackground = defaults.object(forKey: Keys.autoSave) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.filter), let mode = FilterMode(rawValue: raw) {
            filterMode = mode
        } else {
            filterMode = .integer
        }
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 1.0
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.skin), let s = SkinType(rawValue: raw) {
            skin = s
        } else {
            skin = .classic
        }
        showFPS = defaults.object(forKey: Keys.showFPS) as? Bool ?? false
        lowPerformanceMode = defaults.object(forKey: Keys.lowPerf) as? Bool ?? false
    }

    /// 低端机自动降级：CRT 等重滤镜强制关闭
    var effectiveFilter: FilterMode {
        if lowPerformanceMode, filterMode == .crt { return .integer }
        return filterMode
    }
}
