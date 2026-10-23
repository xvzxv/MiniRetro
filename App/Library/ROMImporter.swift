// ROMImporter.swift — ROM 导入：文档选择器 + zip 解压 + 沙盒扫描 + 双保险识别（M5）
import Foundation
import UniformTypeIdentifiers

struct ImportResult {
    var imported: [ROMEntry] = []
    var failed: [(name: String, reason: String)] = []
    var skippedDuplicates = 0
    /// 识别为 BIOS 并安装到 System/ 的文件名（街机 core 依赖）
    var biosInstalled: [String] = []
    /// 识别为金手指文件（.cht）并存入金手指库的名字
    var cheatsImported: [String] = []
    /// 识别为电池存档（.srm/.sav）并归档的名字
    var savesImported: [String] = []
}

enum ROMImporter {
    /// 沙盒 ROM 根目录
    static var romsDirectory: URL {
        FileManager.default.documentsDirectory.appendingPathComponent("ROMs", isDirectory: true)
    }

    /// 街机 BIOS 目录（libretro GET_SYSTEM_DIRECTORY 指向这里）
    static var systemDirectory: URL {
        FileManager.default.documentsDirectory.appendingPathComponent("System", isDirectory: true)
    }

    /// 常见街机 BIOS 包名（zip）：导入时按名字识别，直接装进 System/ 而不是游戏库
    static let biosArchiveNames: Set<String> = [
        "neogeo", "pgm", "pgm3", "skns", "cps1", "cps2", "cps3", "nmk16", "decocass",
    ]

    // MARK: - 识别（魔数 + 扩展名双保险）

    static func identify(data: Data, fileName: String) -> (system: SystemType, coreName: String, byMagic: Bool)? {
        let ext = (fileName as NSString).pathExtension
        let magic = data.withUnsafeBytes { raw -> MRCoreMatch in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return mr_core_for_rom(nil, 0)
            }
            return mr_core_for_rom(base, data.count)
        }
        if let coreNameC = magic.core_name {
            let systemID = String(cString: magic.system_id)
            if let system = SystemType.from(systemID: systemID) {
                return (system, String(cString: coreNameC), true)
            }
        }
        // 扩展名兜底
        let extMatch = mr_core_for_extension(ext)
        if let coreNameC = extMatch.core_name {
            let systemID = String(cString: extMatch.system_id)
            if let system = SystemType.from(systemID: systemID) {
                return (system, String(cString: coreNameC), false)
            }
        }
        return nil
    }

    // MARK: - 导入单文件

    @discardableResult
    static func importFile(from sourceURL: URL, into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        let fileName = sourceURL.lastPathComponent
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            result.failed.append((fileName, "无法读取文件"))
            return result
        }

        let ext = (fileName as NSString).pathExtension.lowercased()

        // 金手指文件：libretro .cht（社区库/自制的标准格式），存进金手指库供游戏内取用
        if ext == "cht" {
            let dir = CheatFileStore.directory
            FileManager.default.ensureDirectory(dir)
            let dest = dir.appendingPathComponent(fileName)
            do {
                try data.write(to: dest, options: .atomic)
                result.cheatsImported.append(fileName)
            } catch {
                result.failed.append((fileName, "金手指写入失败：\(error.localizedDescription)"))
            }
            return result
        }

        // 电池存档：.srm / .sav，按同名 ROM 归档到 Saves/<romID>/
        if ext == "srm" || ext == "sav" {
            let base = (fileName as NSString).deletingPathExtension
            // 兼容「同名被重命名」的情况：store() 遇到重名会写 x-1.nes，
            // 用户手里的存档仍叫 x.srm，这里两种都要能对上
            if let rom = index.roms.first(where: {
                let stem = ($0.fileName as NSString).deletingPathExtension
                return stem == base || stem.hasPrefix(base + "-")
            }) {
                let dir = FileManager.default.documentsDirectory
                    .appendingPathComponent("Saves", isDirectory: true)
                    .appendingPathComponent(rom.id.uuidString, isDirectory: true)
                FileManager.default.ensureDirectory(dir)
                let dest = dir.appendingPathComponent(fileName)
                do {
                    try data.write(to: dest, options: .atomic)
                    result.savesImported.append("\(fileName) → \(rom.displayName)")
                } catch {
                    result.failed.append((fileName, "存档写入失败：\(error.localizedDescription)"))
                }
            } else {
                result.failed.append((fileName, "没有找到同名 ROM（存档需与游戏同名的 .srm/.sav）"))
            }
            return result
        }

        if fileName.lowercased().hasSuffix(".zip") {
            // BIOS 包（neogeo.zip / pgm.zip）不是游戏，装进 System/ 供 core 读取
            let stem = ((fileName as NSString).lastPathComponent as NSString)
                .deletingPathExtension.lowercased()
            if biosArchiveNames.contains(stem) {
                let dir = systemDirectory
                FileManager.default.ensureDirectory(dir)
                let dest = dir.appendingPathComponent(fileName)
                do {
                    try data.write(to: dest, options: .atomic)
                    result.biosInstalled.append(fileName)
                } catch {
                    result.failed.append((fileName, "BIOS 写入失败：\(error.localizedDescription)"))
                }
                return result
            }
            return importZIP(from: sourceURL, into: &index)
        }
        // .7z 只能是街机 romset（主机 ROM 没有用 7z 封装的），原样交给 FBNeo
        if fileName.lowercased().hasSuffix(".7z") {
            return importArcadeArchive(from: sourceURL, into: &index)
        }

        guard let identified = identify(data: data, fileName: fileName) else {
            // 扩展名与文件头都无法识别：仍然落盘并标记损坏，便于用户看到/删除，
            // 而不是只写一条指向不存在文件的索引（旧实现会导致卡片永久显示「文件损坏」）
            var entry = store(data: data, fileName: fileName, system: .fc, byMagic: false)
            entry.isCorrupted = true
            index.upsert(entry)
            result.failed.append((fileName, "扩展名与文件头均无法识别（支持 nes/fds/unf/unif/gb/gbc/gba/zip）"))
            return result
        }

        // 去重：同一款 ROM（文件名 + 字节数 + 系统一致）已在库中就不再落盘第二份，
        // 否则每次重装/重新导入都会在 ROMs 里留下 x-1.nes、x-2.nes 的副本。
        if let existing = index.roms.first(where: {
            $0.system == identified.system
                && $0.fileName == fileName
                && $0.fileSize == Int64(data.count)
        }) {
            if !result.imported.contains(where: { $0.id == existing.id }) {
                result.skippedDuplicates += 1
            }
            return result
        }

        let entry = store(data: data, fileName: fileName, system: identified.system, byMagic: identified.byMagic)
        if index.roms.contains(where: { $0.relativePath == entry.relativePath }) {
            result.skippedDuplicates += 1
            return result
        }
        index.upsert(entry)
        result.imported.append(entry)
        return result
    }

    // MARK: - zip 导入（可能内含多个 ROM）

    /// 用内置 ZipArchive 解压（无第三方依赖，见 App/Library/ZipArchive.swift）
    ///
    /// 两种 zip 语义必须区分：
    ///  1. 「压缩包」——内含 nes/gb/gbc/gba 文件，解压后逐个入库（原有行为）
    ///  2. 「街机 romset」——zip 本身就是一整套街机文件（三国战纪/拳皇的 .zip），
    ///     必须原样保存交给 FBNeo，不能解压（core 需要按 romset 名称打开压缩包）
    static func importZIP(from zipURL: URL, into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        do {
            let entries = try ZipArchive.extract(url: zipURL)
            var consoleEntries: [(path: String, data: Data, identified: (system: SystemType, coreName: String, byMagic: Bool))] = []
            var hasArcadePayload = false

            for entry in entries {
                let fileName = (entry.path as NSString).lastPathComponent
                // 跳过隐藏文件与 macOS 元数据
                guard !fileName.hasPrefix("."), !entry.path.contains("__MACOSX") else { continue }
                if let identified = identify(data: entry.data, fileName: fileName) {
                    consoleEntries.append((entry.path, entry.data, identified))
                } else if Self.arcadeFileExtension(fileName) != nil {
                    hasArcadePayload = true
                }
            }

            if consoleEntries.isEmpty {
                // 没有主机 ROM：按街机 romset 处理（同为 zip，但整套交给 FBNeo）
                if hasArcadePayload || entries.contains(where: { !$0.path.hasSuffix("/") }) {
                    return importArcadeArchive(from: zipURL, into: &index)
                }
                result.failed.append((zipURL.lastPathComponent, "压缩包内没有可识别的 ROM"))
                return result
            }

            for item in consoleEntries {
                let fileName = (item.path as NSString).lastPathComponent
                let stored = store(
                    data: item.data,
                    fileName: fileName,
                    system: item.identified.system,
                    byMagic: item.identified.byMagic
                )
                if index.roms.contains(where: { $0.relativePath == stored.relativePath }) {
                    result.skippedDuplicates += 1
                    continue
                }
                index.upsert(stored)
                result.imported.append(stored)
            }
        } catch {
            // 不是有效 zip（例如损坏或用了 ZIP64）→ 也按街机 romset 再试一次
            let arcade = importArcadeArchive(from: zipURL, into: &index)
            if !arcade.imported.isEmpty { return arcade }
            result.failed.append((zipURL.lastPathComponent, error.localizedDescription))
        }
        return result
    }

    /// 街机 romset 内部常见文件后缀（用于和普通压缩包区分）
    private static func arcadeFileExtension(_ name: String) -> String? {
        let arcadeLike: Set<String> = [
            "bin", "rom", "pcm", "gfx", "snd", "nv", "data", "cslot", "cpu",
            "key", "m1", "m2", "v1", "v2", "c1", "c2", "s1", "sprites",
        ]
        let ext = (name as NSString).pathExtension.lowercased()
        return arcadeLike.contains(ext) ? ext : nil
    }

    /// 把压缩包作为街机游戏导入。
    ///
    /// 必须处理两种真实世界形态（否则 FBNeo 一律加载失败）：
    ///  1. **裸 romset**：zip 内直接是 a0600.rom 这类文件，文件名必须等于内核驱动名（如 kovsh.zip）
    ///  2. **整合包/壳包**：外层 zip 里套着 `<驱动名>.zip` 甚至还有模拟器 exe、ini、说明文件。
    ///     这种整个丢给 core 必然失败（驱动名对不上），必须取出内层 romset。
    /// 顺带把包内的 BIOS（neogeo.zip / pgm.zip…）装进 System/。
    @discardableResult
    static func importArcadeArchive(from sourceURL: URL, into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        let fileName = sourceURL.lastPathComponent
        guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
            result.failed.append((fileName, "无法读取文件"))
            return result
        }
        return importArcadeData(data, fileName: fileName, into: &index, result: &result)
    }

    /// 街机包解析核心：拆 BIOS、拆内层 romset，都不成立才原样入库
    @discardableResult
    private static func importArcadeData(
        _ data: Data,
        fileName: String,
        into index: inout LibraryIndex,
        result: inout ImportResult
    ) -> ImportResult {
        let package = inspectArcadePackage(data)

        // 1) 包里的 BIOS 先装进 System/
        for (biosName, biosData) in package.bios {
            installBIOS(data: biosData, fileName: biosName, result: &result)
        }

        // 2) 有内层 romset（壳包/整合包）→ 逐个入库，外层丢弃
        if !package.romsets.isEmpty {
            for (innerName, innerData) in package.romsets {
                let dest = store(data: innerData, fileName: innerName, system: .arcade, byMagic: false)
                if index.roms.contains(where: { $0.relativePath == dest.relativePath }) {
                    result.skippedDuplicates += 1
                    continue
                }
                index.upsert(dest)
                result.imported.append(dest)
            }
            return result
        }

        // 3) 裸 romset：原样入库（.7z 或被 ZIP64 挡住的 zip 都走这里）
        let dest = store(data: data, fileName: fileName, system: .arcade, byMagic: false)
        if index.roms.contains(where: { $0.relativePath == dest.relativePath }) {
            result.skippedDuplicates += 1
            return result
        }
        index.upsert(dest)
        result.imported.append(dest)
        return result
    }

    /// 解析结果：BIOS 文件 + 内层 romset
    private struct ArcadePackage {
        var bios: [(name: String, data: Data)] = []
        var romsets: [(name: String, data: Data)] = []
        /// 是否属于「壳包」（有内层压缩包，说明外层不是 romset 本体）
        var isWrapper: Bool { !romsets.isEmpty }
    }

    /// 拆包：识别 BIOS 与内层 zip/7z；普通文件（ini/exe/说明）忽略
    private static func inspectArcadePackage(_ data: Data) -> ArcadePackage {
        var package = ArcadePackage()
        guard let entries = try? ZipArchive.extract(data: data) else { return package }

        let archiveExts: Set<String> = ["zip", "7z"]
        for entry in entries {
            let name = (entry.path as NSString).lastPathComponent
            guard !name.hasPrefix("."), !entry.path.contains("__MACOSX") else { continue }
            let stem = (name as NSString).deletingPathExtension.lowercased()
            let ext = (name as NSString).pathExtension.lowercased()

            if archiveExts.contains(ext) {
                if biosArchiveNames.contains(stem) {
                    package.bios.append((name, entry.data))
                } else if entry.data.count > 1024 {   // 排除空壳占位
                    package.romsets.append((name, entry.data))
                }
            }
        }
        return package
    }

    /// 写入 System/ 供 core 通过 GET_SYSTEM_DIRECTORY 找到
    private static func installBIOS(data: Data, fileName: String, result: inout ImportResult) {
        let dir = systemDirectory
        FileManager.default.ensureDirectory(dir)
        do {
            try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            if !result.biosInstalled.contains(fileName) {
                result.biosInstalled.append(fileName)
            }
        } catch {
            result.failed.append((fileName, "BIOS 写入失败：\(error.localizedDescription)"))
        }
    }

    // MARK: - 落盘

    /// 写入 Documents/ROMs/<System>/<文件名>，返回库条目
    @discardableResult
    static func store(data: Data, fileName: String, system: SystemType, byMagic: Bool) -> ROMEntry {
        let dir = romsDirectory.appendingPathComponent(system.rawValue, isDirectory: true)
        FileManager.default.ensureDirectory(dir)
        var destURL = dir.appendingPathComponent(fileName)
        // 同名冲突：追加序号
        var serial = 1
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: destURL.path) {
            destURL = dir.appendingPathComponent("\(base)-\(serial).\(ext)")
            serial += 1
        }
        try? data.write(to: destURL, options: .atomic)
        let relative = "\(system.rawValue)/\(destURL.lastPathComponent)"
        return ROMEntry(
            fileName: destURL.lastPathComponent,
            relativePath: relative,
            system: system,
            fileSize: Int64(data.count),
            detectedByMagic: byMagic
        )
    }

    // MARK: - 沙盒扫描（增量：已有条目跳过）

    @discardableResult
    /// 递归扫描 Documents/ROMs 下**所有**文件（不依赖子目录命名），
    /// 用内容/扩展名识别后建索引。已在 ROMs 内的文件原地建索引，不重复拷贝。
    ///
    /// 历史实现按「子目录名 == SystemType.rawValue」过滤，导致用户手工放入
    /// `ROMs/nes/`、`ROMs/中文目录/` 的文件完全扫不到（与 SystemType 映射缺陷同源）。
    ///
    /// 同时做两件「自愈」的事（修复「每次重启多出一个文件已损坏条目」）：
    ///  1. 索引里指向不存在文件的条目**直接删除**（旧实现只打 isCorrupted 标记，幽灵条目永久残留）
    ///  2. 指向同一文件的重复条目合并（老版本写出的 `ROMs/xxx` 前缀路径会与扫描结果撞车）
    static func scanExisting(into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        let fm = FileManager.default
        guard fm.fileExists(atPath: romsDirectory.path) else { return result }

        index.normalize()
        let knownPaths = Set(index.roms.map(\.relativePath))
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: romsDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return result }

        let prefix = romsDirectory.path + "/"
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }

            let fileName = fileURL.lastPathComponent
            let relative = fileURL.path.hasPrefix(prefix)
                ? String(fileURL.path.dropFirst(prefix.count))
                : fileName
            if knownPaths.contains(relative) { continue }

            guard let data = fm.contents(atPath: fileURL.path) else { continue }

            // 街机 romset：整包入库，不解压（.7z 只能这样处理）
            if fileName.lowercased().hasSuffix(".7z") {
                let entry = ROMEntry(
                    fileName: fileName,
                    relativePath: relative,
                    system: .arcade,
                    fileSize: Int64(data.count),
                    detectedByMagic: false
                )
                index.upsert(entry)
                result.imported.append(entry)
                continue
            }

            guard let identified = identify(data: data, fileName: fileName) else { continue }

            let entry = ROMEntry(
                fileName: fileName,
                relativePath: relative,
                system: identified.system,
                fileSize: Int64(data.count),
                detectedByMagic: identified.byMagic
            )
            index.upsert(entry)
            result.imported.append(entry)
        }

        // 自愈：清掉文件已不存在的条目（改名/删除/旧版本遗留的失效路径），
        // 保留真正损坏但仍在磁盘上的文件（那些条目文件存在，只是内容无法识别）。
        let before = index.roms.count
        index.roms.removeAll { entry in
            let path = romsDirectory.appendingPathComponent(entry.relativePath).path
            return !fm.fileExists(atPath: path)
        }
        for idx in index.roms.indices {
            index.roms[idx].isCorrupted = false
        }
        if index.roms.count != before {
            MRLog.info("已清理 \(before - index.roms.count) 条失效索引（文件不存在）")
        }

        // 自愈：v1.8 及以前把「壳包」整个当 romset 存了（例如 kovsh_v13.zip 里套着 kovsh.zip），
        // FBNeo 按文件名认驱动名，必然失败。这里在启动扫描时自动拆包替换。
        let wrapperCandidates = index.roms.filter {
            $0.system == .arcade && $0.fileName.lowercased().hasSuffix(".zip")
        }
        for entry in wrapperCandidates {
            let url = romsDirectory.appendingPathComponent(entry.relativePath)
            guard let data = fm.contents(atPath: url.path) else { continue }
            let package = inspectArcadePackage(data)
            guard package.isWrapper else { continue }

            for (biosName, biosData) in package.bios {
                var scratch = ImportResult()
                installBIOS(data: biosData, fileName: biosName, result: &scratch)
            }
            for (innerName, innerData) in package.romsets {
                let dest = store(data: innerData, fileName: innerName, system: .arcade, byMagic: false)
                if !index.roms.contains(where: { $0.relativePath == dest.relativePath }) {
                    index.upsert(dest)
                }
            }
            try? fm.removeItem(at: url)
            index.remove(id: entry.id)
            MRLog.info("已拆分壳包 \(entry.fileName) → \(package.romsets.map(\.name).joined(separator: ", "))")
        }
        return result
    }
}
