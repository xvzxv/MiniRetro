// CommunityCheatService.swift — 社区金手指检索（v1.7 新增）
//
// 数据源：libretro-database 的 cht 目录（社区维护，覆盖 FC/GB/GBC/GBA 等平台）。
//   https://github.com/libretro/libretro-database/tree/master/cht
//
// 设计要点（为何不在运行时调 GitHub API）：
//   1. GitHub 未认证 API 限流 60 次/小时，且共享出口 IP 常被打满 → 直接 403；
//   2. 未注册 App 无法做搜索，只能列目录再逐个猜文件名；
//   3. 因此把「平台 → 游戏名清单」预生成为 CheatIndex.json 打进 App（约数百 KB），
//      搜索完全离线；只有命中后抓具体 .cht 才走 raw.githubusercontent.com（无 API 限流）。
//
// 索引生成脚本见 Tools/gen_cheat_index.sh（构建期更新，不影响运行期）。
import Foundation

// MARK: - 匹配结果

struct CommunityCheatFile: Identifiable, Hashable {
    var id: String { "\(systemKey)/\(fileName)" }
    /// 索引 key（fc/gb/gbc/gba）
    let systemKey: String
    /// 数据库目录名（如 "Nintendo - Nintendo Entertainment System"）
    let folder: String
    /// 索引里的文件名（如 "Contra (USA).cht"）
    let fileName: String

    var displayTitle: String {
        (fileName as NSString).deletingPathExtension
    }
}

struct CommunityCheat: Identifiable, Equatable {
    var id = UUID()
    var desc: String
    var code: String
    var type: CheatEntry.CheatType
    var isSelected: Bool = true
}

// MARK: - 服务

enum CommunityCheatService {
    enum ServiceError: LocalizedError {
        case indexMissing
        case noMatch(String)
        case network(String)
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .indexMissing:
                return "内置金手指索引缺失（打包时未生成 CheatIndex.json）"
            case .noMatch(let q):
                return "社区库里没有匹配「\(q)」的游戏，可换个关键词（建议用英文名，如 Contra）"
            case .network(let msg):
                return "网络请求失败：\(msg)"
            case .emptyFile:
                return "该游戏在社区库里没有可用代码"
            }
        }
    }

    /// 平台 → 数据库目录名
    static func folder(for system: SystemType) -> String? {
        switch system {
        case .fc, .fds: return "Nintendo - Nintendo Entertainment System"
        case .gb: return "Nintendo - Game Boy"
        case .gbc: return "Nintendo - Game Boy Color"
        case .gba: return "Nintendo - Game Boy Advance"
        case .arcade: return "MAME"   // 索引未打包 MAME；街机金手指请手动录入
        }
    }

    // MARK: 索引

    private struct Index: Decodable {
        struct Platform: Decodable {
            let folder: String
            let files: [String]
        }
        let generated: String?
        let platforms: [String: Platform]
    }

    private static var cachedIndex: Index?

    private static func loadIndex() -> Index? {
        if let cachedIndex { return cachedIndex }
        let candidates = [
            Bundle.main.url(forResource: "CheatIndex", withExtension: "json"),
            Bundle.main.url(forResource: "CheatIndex", withExtension: "json", subdirectory: "Resources"),
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let index = try? JSONDecoder().decode(Index.self, from: data) {
                cachedIndex = index
                return index
            }
        }
        return nil
    }

    // MARK: 搜索

    /// 归一化：小写、去掉括号内容与所有非字母数字（中文保留）
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // 去掉 (USA)/(Japan)/[!] 这类标记
        s = s.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^0-9a-z\\u4e00-\\u9fa5]+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func search(query: String, system: SystemType, limit: Int = 12) -> [CommunityCheatFile] {
        guard let index = loadIndex(), folder(for: system) != nil else { return [] }
        let key = indexKey(for: system)
        guard let platform = index.platforms[key] else { return [] }

        let q = normalize(query)
        guard !q.isEmpty else { return [] }

        var scored: [(score: Int, file: CommunityCheatFile)] = []
        for file in platform.files {
            let name = normalize((file as NSString).deletingPathExtension)
            guard !name.isEmpty else { continue }
            var score = 0
            if name == q {
                score = 100
            } else if name.hasPrefix(q) {
                score = 80
            } else if q.hasPrefix(name) {
                score = 70
            } else if name.contains(q) {
                score = 60
            } else if q.contains(name) {
                score = 50
            } else {
                // 词重合：取交集词数
                let qTokens = Set(q.split(separator: " ").map(String.init))
                let nTokens = Set(name.split(separator: " ").map(String.init))
                let overlap = qTokens.intersection(nTokens).count
                if overlap > 0, qTokens.count > 0 {
                    score = 20 + overlap * 8
                }
            }
            if score > 0 {
                scored.append((score, CommunityCheatFile(
                    systemKey: key, folder: platform.folder, fileName: file
                )))
            }
        }
        return scored
            .sorted { $0.score == $1.score ? $0.file.fileName < $1.file.fileName : $0.score > $1.score }
            .prefix(limit)
            .map(\.file)
    }

    private static func indexKey(for system: SystemType) -> String {
        switch system {
        case .fc, .fds: return "fc"
        case .gb: return "gb"
        case .gbc: return "gbc"
        case .gba: return "gba"
        case .arcade: return "arcade"
        }
    }

    // MARK: 抓取与解析

    private static func rawURL(for file: CommunityCheatFile) -> URL? {
        var components = URLComponents(string: "https://raw.githubusercontent.com")
        // 目录名与文件名都可能含空格/&#39; 等字符，逐段编码
        var path = "/libretro/libretro-database/master/cht/"
        let encodedFolder = file.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.folder
        let encodedName = file.fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.fileName
        path += encodedFolder + "/" + encodedName
        components?.percentEncodedPath = path
        return components?.url
    }

    static func fetchCheats(for file: CommunityCheatFile, system: SystemType) async throws -> [CommunityCheat] {
        guard let url = rawURL(for: file) else { throw ServiceError.network("URL 非法") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("MiniRetro/1.7 (iOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (payload, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw ServiceError.network("HTTP \(http.statusCode)")
            }
            data = payload
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }

        guard let text = String(data: data, encoding: .utf8) else { throw ServiceError.emptyFile }
        let parsed = parse(text: text, system: system)
        if parsed.isEmpty { throw ServiceError.emptyFile }
        return parsed
    }

    /// 解析 libretro .cht（cheats = N / cheatN_desc / cheatN_code）
    static func parse(text: String, system: SystemType) -> [CommunityCheat] {
        var descs: [Int: String] = [:]
        var codes: [Int: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("cheat") else { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let lhs = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var rhs = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if rhs.hasPrefix("\""), rhs.hasSuffix("\""), rhs.count >= 2 {
                rhs = String(rhs.dropFirst().dropLast())
            }
            if lhs.hasPrefix("cheat"), let underscore = lhs.lastIndex(of: "_") {
                let idxText = String(lhs[lhs.index(lhs.startIndex, offsetBy: 5)..<underscore])
                guard let idx = Int(idxText) else { continue }
                let field = String(lhs[lhs.index(after: underscore)...])
                if field == "desc" { descs[idx] = rhs }
                if field == "code" { codes[idx] = rhs }
            }
        }
        let indices = Set(descs.keys).union(codes.keys).sorted()
        return indices.compactMap { idx in
            guard let code = codes[idx], !code.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let desc = descs[idx] ?? "金手指 \(idx + 1)"
            return CommunityCheat(
                desc: desc,
                code: code,
                type: inferType(code: code, system: system),
                isSelected: false
            )
        }
    }

    /// 按代码形态推断类型（libretro 的 cht 不写类型）
    static func inferType(code: String, system: SystemType) -> CheatEntry.CheatType {
        let upper = code.uppercased().trimmingCharacters(in: .whitespaces)
        // 社区库最常见的是 `地址:值`（如 00AE:41 / 1C2A:63），core 直接写内存
        if upper.contains(":"), upper.split(separator: ":").count == 2 {
            return .rawRAM
        }
        switch system {
        case .fc, .fds:
            // NES Game Genie 含 GHIJKLNOPQRSTUVWXYZ 之类字母或 6/8 位字母数字
            let letters = upper.filter { $0.isLetter && !"ABCDEF".contains($0) }
            return letters.isEmpty ? .gameShark : .gameGenie
        case .gb, .gbc:
            // GB Game Genie: XXX-YYY-ZZZ（9 位 hex 分三段）
            let parts = upper.split(separator: "-")
            if parts.count == 3, parts.allSatisfy({ $0.count == 3 }) { return .gameGenie }
            return .gameShark
        case .gba:
            return .gameShark
        case .arcade:
            return .gameShark
        }
    }
}
