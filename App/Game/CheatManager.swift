// CheatManager.swift — 金手指管理（M2/M3/M4）
// 持久化：Documents/Cheats/<romID>.json
// 生效路径：retro_cheat_reset + retro_cheat_set（ADR-003；SameBoy 走构建期补丁启用原生 cheat）
import Foundation

final class CheatManager: ObservableObject {
    @Published private(set) var cheats: [CheatEntry] = []

    private let romID: UUID
    private let retroCore: RetroCore

    init(romID: UUID, retroCore: RetroCore) {
        self.romID = romID
        self.retroCore = retroCore
        load()
    }

    private var storageURL: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Cheats", isDirectory: true)
            .appendingPathComponent("\(romID.uuidString).json")
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CheatEntry].self, from: data) else {
            cheats = []
            return
        }
        cheats = decoded
        applyAll()
    }

    func save() {
        let dir = storageURL.deletingLastPathComponent()
        FileManager.default.ensureDirectory(dir)
        if let data = try? JSONEncoder().encode(cheats) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    func add(name: String, code: String, type: CheatEntry.CheatType) {
        let entry = CheatEntry(name: name, code: code, type: type, isEnabled: true)
        cheats.append(entry)
        save()
        applyAll()
    }

    func update(_ entry: CheatEntry) {
        if let idx = cheats.firstIndex(where: { $0.id == entry.id }) {
            cheats[idx] = entry
            save()
            applyAll()
        }
    }

    func remove(_ entry: CheatEntry) {
        cheats.removeAll { $0.id == entry.id }
        save()
        applyAll()
    }

    func toggle(_ entry: CheatEntry) {
        if let idx = cheats.firstIndex(where: { $0.id == entry.id }) {
            cheats[idx].isEnabled.toggle()
            save()
            applyAll()
        }
    }

    /// 全量重新下发（reset 后按索引设置）
    func applyAll() {
        retroCore.resetCheats()
        for (index, entry) in cheats.enumerated() where entry.isEnabled {
            retroCore.setCheat(at: UInt(index), enabled: true, withCode: entry.code)
        }
    }
}
