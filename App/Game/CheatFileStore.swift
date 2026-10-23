// CheatFileStore.swift — 导入的金手指文件库（.cht）（v1.10）
//
// 为什么要单独存：.cht 是 libretro 社区通用的金手指格式（`cheats = N` + cheatN_desc/code）。
// 用户从社区下载后直接拖进 App 时，不该「因为不是 ROM 就被丢掉」——
// 这里把文件存进 Documents/Cheats/Imported，游戏内金手指页可挑一个套用到当前游戏。
import Foundation

struct ImportedCheatFile: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: String { url.lastPathComponent }
}

enum CheatFileStore {
    static var directory: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Cheats", isDirectory: true)
            .appendingPathComponent("Imported", isDirectory: true)
    }

    static func list() -> [ImportedCheatFile] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "cht" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ImportedCheatFile(name: $0.lastPathComponent, url: $0) }
    }

    static func remove(_ file: ImportedCheatFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    /// 解析成可导入的条目（复用社区库的 .cht 解析器，类型按代码形态推断）
    static func parse(_ file: ImportedCheatFile, system: SystemType) -> [CommunityCheat] {
        guard let data = try? Data(contentsOf: file.url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return CommunityCheatService.parse(text: text, system: system)
    }
}
