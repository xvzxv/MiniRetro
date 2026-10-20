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
              let decoded = try? JSONDecoder().decode(LibraryIndex.self, from: data) else {
            index = LibraryIndex()
            return
        }
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

        for url in urls {
            let result = ROMImporter.importFile(from: url, into: &index)
            totalImported += result.imported.count
            duplicates += result.skippedDuplicates
            totalFailed.append(contentsOf: result.failed)
        }
        persist()

        summaryParts.append("导入 \(totalImported) 款")
        if duplicates > 0 { summaryParts.append("跳过重复 \(duplicates) 款") }
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
        // 同步删除存档目录
        let savesDir = FileManager.default.documentsDirectory
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(rom.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: savesDir)
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
