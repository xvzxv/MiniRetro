// RemoteImportService.swift — 远程导入：HTTP 直链 + WebDAV（v1.9）
//
// 为什么不做「夸克网盘接口」：
//   夸克/百度这类网盘没有公开 API，网上流传的都是逆向出来的 Cookie 接口，
//   要在 App 里存用户的账号 Cookie，接口一改就废，还会把账号暴露在本地存储里。
//   WebDAV 是标准协议（群晖、坚果云、Nextcloud、InfiniCLOUD 都支持），
//   配合「直链下载」已经能覆盖「把自己的 ROM 从远程拿回来」这个真实需求。
import Foundation

// MARK: - 数据模型

struct RemoteFileItem: Identifiable, Hashable {
    let name: String
    /// 完整 URL（WebDAV 的 href 可能是绝对路径，需要拼上 host）
    let url: URL
    let isDirectory: Bool
    let size: Int64?

    var id: String { url.absoluteString }

    var displaySize: String {
        guard let size, !isDirectory else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 是否是本 App 能直接导入的格式
    var isImportable: Bool {
        let ext = url.pathExtension.lowercased()
        return ["nes", "fds", "unf", "unif", "gb", "gbc", "gba", "zip", "7z"].contains(ext)
    }
}

struct WebDAVCredential: Codable, Equatable {
    var server: String
    var username: String
    var password: String
}

enum RemoteImportError: LocalizedError {
    case badURL
    case http(Int)
    case emptyResponse
    case notXML
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badURL: return "地址格式不对（需要 http:// 或 https:// 开头）"
        case .http(let code): return "服务器返回 HTTP \(code)"
        case .emptyResponse: return "服务器没有返回内容"
        case .notXML: return "目录列表解析失败（服务器可能不是 WebDAV）"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - 服务

enum RemoteImportService {
    /// 下载到临时文件并返回本地 URL（调用方负责导入后删除）
    static func download(
        url: URL,
        headers: [String: String] = [:],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("MiniRetro/1.9 (iOS)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteImportError.http(http.statusCode)
        }
        let total = max(response.expectedContentLength, 0)
        let name = response.suggestedFilename
            ?? (url.lastPathComponent.isEmpty ? "download.bin" : url.lastPathComponent)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteImport", isDirectory: true)
        FileManager.default.ensureDirectory(dir)
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)

        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var received: Int64 = 0
        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    progress(min(1.0, Double(received) / Double(total)))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        progress(1.0)

        guard received > 0 else {
            try? FileManager.default.removeItem(at: dest)
            throw RemoteImportError.emptyResponse
        }
        return dest
    }

    // MARK: WebDAV

    static func basicAuthHeader(_ credential: WebDAVCredential) -> [String: String] {
        let raw = "\(credential.username):\(credential.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return ["Authorization": "Basic \(encoded)"]
    }

    /// PROPFIND 列目录（Depth: 1）
    static func listWebDAV(
        server: URL,
        path: String,
        credential: WebDAVCredential
    ) async throws -> [RemoteFileItem] {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = 20
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("MiniRetro/1.9 (iOS)", forHTTPHeaderField: "User-Agent")
        for (key, value) in basicAuthHeader(credential) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:"><d:prop>
        <d:displayname/><d:resourcetype/><d:getcontentlength/>
        </d:prop></d:propfind>
        """
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteImportError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw RemoteImportError.emptyResponse }

        let parser = WebDAVMultiStatusParser(server: server, basePath: path)
        guard parser.parse(data) else { throw RemoteImportError.notXML }

        // 去掉「当前目录自己」这一条
        let current = server.appendingPathComponent(path).standardizedFileURL.path
        return parser.items
            .filter { $0.url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                != current.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

// MARK: - PROPFIND 解析

final class WebDAVMultiStatusParser: NSObject, XMLParserDelegate {
    private let server: URL
    private let basePath: String
    private(set) var items: [RemoteFileItem] = []

    private var currentHref: String?
    private var currentIsDirectory = false
    private var currentLength: Int64?
    private var currentDisplayName: String?
    private var inResponse = false

    init(server: URL, basePath: String) {
        self.server = server
        self.basePath = basePath
    }

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        return parser.parse()
    }

    /// 去掉命名空间前缀（`D:href` → `href`）
    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "response":
            inResponse = true
            currentHref = nil
            currentIsDirectory = false
            currentLength = nil
            currentDisplayName = nil
        case "collection":
            if inResponse { currentIsDirectory = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inResponse else { return }
        // 由调用方在 didEndElement 里根据当前元素判断，这里只做简单累积
        pendingText += string
    }

    private var pendingText = ""
    private var currentElement = ""

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""

        guard inResponse else { return }
        switch name {
        case "href":
            currentHref = text
        case "getcontentlength":
            currentLength = Int64(text)
        case "displayname":
            currentDisplayName = text.isEmpty ? nil : text
        case "response":
            inResponse = false
            defer { currentHref = nil }
            guard let href = currentHref, let url = resolve(href) else { return }
            let fallback = url.lastPathComponent
            let display = currentDisplayName ?? fallback
            items.append(RemoteFileItem(
                name: display.removingPercentEncoding ?? display,
                url: url,
                isDirectory: currentIsDirectory,
                size: currentLength
            ))
        default:
            break
        }
    }

    /// href 可能是 `/dav/xxx` 这种绝对路径，也可能是完整 URL
    private func resolve(_ href: String) -> URL? {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            return URL(string: href)
        }
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.percentEncodedPath = href.hasPrefix("/") ? href : "/" + href
        return components.url
    }
}
