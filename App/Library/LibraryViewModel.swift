// LibraryViewModel.swift — 游戏库数据驱动（M5）
import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var roms: [ROMEntry] = []
    @Published var showImporter = false
    @Published var importSummary: String?

    private var index: LibraryIndex
    private let indexURL: URL

    init() {
        let dir = FileManager.default.documentsDirectory.appendingPathComponent("Library", isDirectory: true)
        FileManager.default.ensureDirectory(dir)
        indexURL = dir.appendingPathComponent("index.json")
        index = LibraryIndex()
        loadIndex()
        scanAndRefresh()
    }

    // MARK: - 持久化

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              var decoded = try? JSONDecoder().decode(LibraryIndex.self, from: data) else {
            index = LibraryIndex()
            return
        }
        // 旧索引可能带 ROMs/ 前缀或存在重复条目，先归一化再用于比对
        decoded.normalize()
        index = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
        roms = index.roms
    }

    /// 启动时扫描沙盒 + 校验文件存在性（增量）
    private func scanAndRefresh() {
        let result = ROMImporter.scanExisting(into: &index)
        if !result.imported.isEmpty {
            MRLog.info("扫描新增 ROM \(result.imported.count) 款")
        }
        persist()
    }

    // MARK: - 导入

    func importFiles(urls: [URL]) {
        var summaryParts: [String] = []
        var totalImported = 0
        var totalFailed: [(String, String)] = []
        var duplicates = 0
        var bios: [String] = []
        var cheats: [String] = []
        var saves: [String] = []

        for url in urls {
            let result = ROMImporter.importFile(from: url, into: &index)
            totalImported += result.imported.count
            duplicates += result.skippedDuplicates
            totalFailed.append(contentsOf: result.failed)
            bios.append(contentsOf: result.biosInstalled)
            cheats.append(contentsOf: result.cheatsImported)
            saves.append(contentsOf: result.savesImported)
        }
        persist()

        summaryParts.append("导入 \(totalImported) 款")
        if duplicates > 0 { summaryParts.append("跳过重复 \(duplicates) 款") }
        if !bios.isEmpty {
            summaryParts.append("已安装 BIOS：\(bios.joined(separator: "、"))")
        }
        if !cheats.isEmpty {
            summaryParts.append("已存入金手指库：\(cheats.joined(separator: "、"))（游戏内金手指页可套用）")
        }
        if !saves.isEmpty {
            summaryParts.append("已归档电池存档：\(saves.joined(separator: "、"))")
        }
        for (name, reason) in totalFailed.prefix(3) {
            summaryParts.append("\(name)：\(reason)")
        }
        importSummary = summaryParts.joined(separator: "\n")
    }

    // MARK: - 操作

    func toggleFavorite(_ rom: ROMEntry) {
        if let idx = index.roms.firstIndex(where: { $0.id == rom.id }) {
            index.roms[idx].isFavorite.toggle()
            persist()
        }
    }

    func remove(_ rom: ROMEntry) {
        index.remove(id: rom.id)
        // 同步删除 ROM 文件本体：只删索引的话，下次启动扫描会把文件重新加回库，
        // 用户会看到「删不掉的条目」（旧版本「文件已损坏」删不干净就是这个原因）。
        let fileURL = ROMImporter.romsDirectory.appendingPathComponent(rom.relativePath)
        try? FileManager.default.removeItem(at: fileURL)
        // 同步删除存档目录
        let savesDir = FileManager.default.documentsDirectory
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(rom.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: savesDir)
        // 同步删除金手指记录，避免 ID 复用时串味
        let cheatURL = FileManager.default.documentsDirectory
            .appendingPathComponent("Cheats", isDirectory: true)
            .appendingPathComponent("\(rom.id.uuidString).json")
        try? FileManager.default.removeItem(at: cheatURL)
        persist()
    }

    func markPlayed(_ rom: ROMEntry) {
        if let idx = index.roms.firstIndex(where: { $0.id == rom.id }) {
            index.roms[idx].lastPlayed = Date()
            persist()
        }
    }

    // MARK: - 查询

    func filteredROMs(searchText: String, favoritesOnly: Bool) -> [ROMEntry] {
        var list = roms
        if favoritesOnly {
            list = list.filter(\.isFavorite)
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.system.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list.sorted { lhs, rhs in
            let l = lhs.lastPlayed ?? .distantPast
            let r = rhs.lastPlayed ?? .distantPast
            if l != r { return l > r }
            return lhs.dateAdded > rhs.dateAdded
        }
    }

    // MARK: - 封面（取该 ROM 最新缩略图）

    func coverImage(for rom: ROMEntry) -> CrossImage? {
        let thumbsDir = FileManager.default.documentsDirectory
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(rom.id.uuidString, isDirectory: true)
            .appendingPathComponent("thumbs", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: thumbsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        let images = files
            .filter { $0.pathExtension == "png" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
        guard let latest = images.first,
              let data = try? Data(contentsOf: latest) else { return nil }
        return CrossImage(data: data)
    }
}
