// ROMImporter.swift — ROM 导入：文档选择器 + zip 解压 + 沙盒扫描 + 双保险识别（M5）
import Foundation
import UniformTypeIdentifiers

struct ImportResult {
    var imported: [ROMEntry] = []
    var failed: [(name: String, reason: String)] = []
    var skippedDuplicates = 0
}

enum ROMImporter {
    /// 沙盒 ROM 根目录
    static var romsDirectory: URL {
        FileManager.default.documentsDirectory.appendingPathComponent("ROMs", isDirectory: true)
    }

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

        if fileName.lowercased().hasSuffix(".zip") {
            return importZIP(from: sourceURL, into: &index)
        }

        guard let identified = identify(data: data, fileName: fileName) else {
            // 扩展名与文件头都无法识别：仍然落盘并标记损坏，便于用户看到/删除，
            // 而不是只写一条指向不存在文件的索引（旧实现会导致卡片永久显示「文件损坏」）
            var entry = store(data: data, fileName: fileName, system: .fc, byMagic: false)
            entry.isCorrupted = true
            index.upsert(entry)
            result.failed.append((fileName, "扩展名与文件头均无法识别（支持 nes/fds/unf/unif/gb/gbc/gba）"))
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
    static func importZIP(from zipURL: URL, into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        do {
            let entries = try ZipArchive.extract(url: zipURL)
            for entry in entries {
                let fileName = (entry.path as NSString).lastPathComponent
                // 跳过隐藏文件与 macOS 元数据
                guard !fileName.hasPrefix("."), !entry.path.contains("__MACOSX") else { continue }
                guard let identified = identify(data: entry.data, fileName: fileName) else {
                    continue // 压缩包内的非 ROM 文件静默跳过
                }
                let stored = store(
                    data: entry.data,
                    fileName: fileName,
                    system: identified.system,
                    byMagic: identified.byMagic
                )
                if index.roms.contains(where: { $0.relativePath == stored.relativePath }) {
                    result.skippedDuplicates += 1
                    continue
                }
                index.upsert(stored)
                result.imported.append(stored)
            }
        } catch {
            result.failed.append((zipURL.lastPathComponent, error.localizedDescription))
        }
        return result
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
    static func scanExisting(into index: inout LibraryIndex) -> ImportResult {
        var result = ImportResult()
        let fm = FileManager.default
        guard fm.fileExists(atPath: romsDirectory.path) else { return result }

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

            guard let data = fm.contents(atPath: fileURL.path),
                  let identified = identify(data: data, fileName: fileName) else { continue }

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

        // 标记文件缺失/不可读
        for (idx, entry) in index.roms.enumerated() {
            let path = romsDirectory.appendingPathComponent(entry.relativePath).path
            index.roms[idx].isCorrupted = !fm.fileExists(atPath: path)
        }
        return result
    }
}
