// AppTypes.swift — 核心数据模型：系统类型、ROM 条目、库索引
import Foundation

/// 模拟的系统（与 CoreRegistry 的 system_id 对应）
enum SystemType: String, Codable, CaseIterable, Identifiable {
    case fc
    case gb
    case gbc
    case gba
    case fds
    /// 街机（CPS1/CPS2/Neo Geo/PGM）：西游释厄传、三国战纪、拳皇等
    case arcade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fc: return "FC/NES"
        case .gb: return "GB"
        case .gbc: return "GBC"
        case .gba: return "GBA"
        case .fds: return "FDS"
        case .arcade: return "街机"
        }
    }

    /// 对应 libretro core 名（framework 名 = coreName + "_core"）
    var coreName: String {
        switch self {
        case .fc, .fds: return "fceumm"
        case .gb, .gbc: return "sameboy"
        case .gba: return "mgba"
        case .arcade: return "fbneo"
        }
    }

    var supportsLR: Bool {
        self == .gba || self == .arcade
    }

    /// 街机 romset 是 zip/7z 打包的整套文件，必须原样交给 core
    var isArcade: Bool { self == .arcade }

    /// C 层（CoreRegistry.c）返回的 system_id 与枚举 rawValue 并非一一对应：
    /// NES 的 case 名是 fc（历史命名，用于持久化与布局 key），而 C 层返回 "nes"。
    /// 这里用显式映射表，避免依赖字符串巧合。
    static func from(systemID: String) -> SystemType? {
        switch systemID.lowercased() {
        case "nes", "fc", "unf", "unif":
            return .fc
        case "fds":
            return .fds
        case "gb":
            return .gb
        case "gbc":
            return .gbc
        case "gba":
            return .gba
        case "arcade", "fbneo", "mame", "neogeo", "cps1", "cps2", "pgm":
            return .arcade
        default:
            return nil
        }
    }
}

/// 库中的一款 ROM
struct ROMEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var fileName: String
    /// 相对 Documents 的路径（ROMs/子目录保持用户结构）
    var relativePath: String
    var system: SystemType
    var fileSize: Int64
    var dateAdded: Date = Date()
    var lastPlayed: Date?
    var isFavorite: Bool = false
    /// 识别方式：true = 文件头魔数，false = 扩展名兜底
    var detectedByMagic: Bool = false
    /// 索引标记：文件缺失/无法读取时置位，UI 显示损坏标记
    var isCorrupted: Bool = false

    var displayName: String {
        (fileName as NSString).deletingPathExtension
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    // 兼容历史索引：早期版本写出的 index.json 缺少部分字段（isCorrupted / detectedByMagic），
    // 综合解码一旦缺键就整份失败 → 库被清空后重新扫描，表现为「重启后又多出条目」。
    private enum CodingKeys: String, CodingKey {
        case id, fileName, relativePath, system, fileSize
        case dateAdded, lastPlayed, isFavorite, detectedByMagic, isCorrupted
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        relativePath: String,
        system: SystemType,
        fileSize: Int64,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil,
        isFavorite: Bool = false,
        detectedByMagic: Bool = false,
        isCorrupted: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.system = system
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.isFavorite = isFavorite
        self.detectedByMagic = detectedByMagic
        self.isCorrupted = isCorrupted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decode(String.self, forKey: .fileName)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        system = try c.decode(SystemType.self, forKey: .system)
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        detectedByMagic = try c.decodeIfPresent(Bool.self, forKey: .detectedByMagic) ?? false
        isCorrupted = try c.decodeIfPresent(Bool.self, forKey: .isCorrupted) ?? false
    }
}

/// 本地 JSON 索引（Documents/Library/index.json）
struct LibraryIndex: Codable, Equatable {
    /// 索引结构版本：2 起 relativePath 一律相对 Documents/ROMs（旧版可能带 ROMs/ 前缀）
    static let currentVersion = 2

    var version: Int = LibraryIndex.currentVersion
    var roms: [ROMEntry] = []

    mutating func upsert(_ entry: ROMEntry) {
        if let idx = roms.firstIndex(where: { $0.relativePath == entry.relativePath }) {
            var updated = entry
            updated.id = roms[idx].id // 保持稳定 ID
            updated.lastPlayed = roms[idx].lastPlayed ?? entry.lastPlayed
            updated.isFavorite = roms[idx].isFavorite || entry.isFavorite
            roms[idx] = updated
        } else {
            roms.append(entry)
        }
    }

    mutating func remove(id: UUID) {
        roms.removeAll { $0.id == id }
    }

    /// 归一化 historical 数据：把 `ROMs/fc/x.nes` 这类带前缀的路径改成 `fc/x.nes`，
    /// 并去掉指向同一文件的重复条目（保留最早加入的那条，继承收藏/最近游玩信息）。
    mutating func normalize() {
        for idx in roms.indices {
            var path = roms[idx].relativePath
            while path.hasPrefix("ROMs/") {
                path = String(path.dropFirst("ROMs/".count))
            }
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
            roms[idx].relativePath = path
            roms[idx].fileName = (path as NSString).lastPathComponent
        }
        var seen = Set<String>()
        var keep: [ROMEntry] = []
        for entry in roms {
            if seen.contains(entry.relativePath) {
                if let idx = keep.firstIndex(where: { $0.relativePath == entry.relativePath }) {
                    keep[idx].isFavorite = keep[idx].isFavorite || entry.isFavorite
                    keep[idx].lastPlayed = max(
                        keep[idx].lastPlayed ?? .distantPast,
                        entry.lastPlayed ?? .distantPast
                    )
                    if keep[idx].lastPlayed == .distantPast { keep[idx].lastPlayed = nil }
                }
                continue
            }
            seen.insert(entry.relativePath)
            keep.append(entry)
        }
        roms = keep
        version = LibraryIndex.currentVersion
    }
}

/// 金手指条目
struct CheatEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var code: String
    var type: CheatType
    var isEnabled: Bool = true

    enum CheatType: String, Codable, CaseIterable {
        case gameGenie = "Game Genie"
        case gameShark = "GameShark"
        case actionReplay = "Action Replay"
        case codeBreaker = "CodeBreaker"
        /// libretro 社区库的主流写法：`地址:值`（如 00AE:41），由 core 直接写内存，
        /// 不经过 Game Genie/GameShark 解码。类型只是标注，代码原样下发给 core。
        case rawRAM = "内存写入（地址:值）"
    }
}

/// 即时存档槽位元数据
struct SaveStateEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var slot: Int
    var timestamp: Date
    var thumbnailName: String?
    var isAutoSave: Bool = false
    /// 该槽位是否已有存档（false 时 UI 显示「空」）
    var isOccupied: Bool = false

    /// 存档文件相对 Saves/<romID>/ 的文件名
    var stateFileName: String {
        isAutoSave ? "auto.mrstate" : "slot-\(slot).mrstate"
    }
}
