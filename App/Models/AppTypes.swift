// AppTypes.swift — 核心数据模型：系统类型、ROM 条目、库索引
import Foundation

/// 模拟的系统（与 CoreRegistry 的 system_id 对应）
enum SystemType: String, Codable, CaseIterable, Identifiable {
    case fc
    case gb
    case gbc
    case gba
    case fds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fc: return "FC/NES"
        case .gb: return "GB"
        case .gbc: return "GBC"
        case .gba: return "GBA"
        case .fds: return "FDS"
        }
    }

    /// 对应 libretro core 名（framework 名 = coreName + "_core"）
    var coreName: String {
        switch self {
        case .fc, .fds: return "fceumm"
        case .gb, .gbc: return "sameboy"
        case .gba: return "mgba"
        }
    }

    var supportsLR: Bool {
        self == .gba
    }

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
}

/// 本地 JSON 索引（Documents/Library/index.json）
struct LibraryIndex: Codable, Equatable {
    var version: Int = 1
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
}

/// 金手指条目
struct CheatEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var code: String
    var type: CheatType
    var isEnabled: Bool = true

    enum CheatType: String, Codable, CaseIterable {
        case gameShark = "GameShark"
        case actionReplay = "Action Replay"
        case codeBreaker = "CodeBreaker"
        case gameGenie = "Game Genie"
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
