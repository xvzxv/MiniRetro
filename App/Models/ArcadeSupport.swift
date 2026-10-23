// ArcadeSupport.swift — 街机（FBNeo）运行前条件检查
//
// FBNeo 是按 romset 名称加载整套文件的 core：游戏本体与 BIOS 必须同时在
// system 目录（Documents/System）里，缺 BIOS 时会直接报 romset 不完整。
// 这里只做「是否装了」的展示，不参与加载逻辑。
import Foundation

struct ArcadeBIOSStatus {
    let fileName: String
    let title: String
    let installed: Bool
}

enum ArcadeSupport {
    /// 常见 BIOS 包及对应平台说明
    static var biosRequirements: [ArcadeBIOSStatus] {
        let dir = ROMImporter.systemDirectory
        let items: [(String, String)] = [
            ("neogeo.zip", "Neo Geo / 拳皇系列必需"),
            ("pgm.zip", "PGM / 西游释厄传、三国战纪必需"),
        ]
        return items.map { name, title in
            ArcadeBIOSStatus(
                fileName: name,
                title: title,
                installed: FileManager.default.fileExists(
                    atPath: dir.appendingPathComponent(name).path
                )
            )
        }
    }

    /// 从内核日志判断缺哪些 BIOS。
    ///
    /// FBNeo 找不到 BIOS 时不会让 retro_load_game 失败，只在日志里写：
    ///   `Searching all possible locations for romset pgm`
    ///   `No romset found at .../pgm`（有则写 `Romset found at .../pgm`）
    /// 所以按「搜索 → 是否 found」成对解析，命中即在界面提示，避免用户对着黑屏猜。
    static func missingBIOS(in logLines: [String]) -> [String] {
        var missing = Set<String>()
        var pending: String?
        var found = false

        func settle() {
            if let name = pending, !found, ROMImporter.biosArchiveNames.contains(name) {
                missing.insert(name)
            }
            pending = nil
        }

        for line in logLines {
            if let range = line.range(of: "Searching all possible locations for romset ") {
                settle()
                pending = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                found = false
            } else if pending != nil, line.contains("Romset found at ") {
                found = true
            }
        }
        settle()
        return missing.sorted()
    }

    /// 街机 romset 常见分类（仅用于提示文案）
    static func platformHint(for romName: String) -> String {
        let name = romName.lowercased()
        if name.hasPrefix("kof") || name.contains("mslug") || name.contains("neogeo") {
            return "Neo Geo"
        }
        if name.contains("kov") || name.contains("orlegend") || name.contains("pgm") {
            return "PGM"
        }
        if name.hasPrefix("sf") || name.contains("dino") || name.contains("cps") {
            return "CPS"
        }
        return "街机"
    }
}
