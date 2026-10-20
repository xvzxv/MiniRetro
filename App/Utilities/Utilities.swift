// Utilities.swift — 文件系统辅助与日志
import Foundation

extension FileManager {
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func ensureDirectory(_ url: URL) {
        if !fileExists(atPath: url.path) {
            try? createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

/// 简易日志（debug 输出 + 内存环形缓冲供 App 内查看）
enum MRLog {
    static let queue = DispatchQueue(label: "com.miniretro.log")
    private static var buffer: [String] = []
    private static let maxEntries = 500

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        emit("INFO", message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        emit("ERROR", message, file: file, line: line)
    }

    private static func emit(_ level: String, _ message: String, file: String, line: Int) {
        let name = (file as NSString).lastPathComponent
        let entry = "[\(level)] \(name):\(line) \(message)"
        #if DEBUG
        print(entry)
        #endif
        queue.sync {
            buffer.append(entry)
            if buffer.count > maxEntries {
                buffer.removeFirst(buffer.count - maxEntries)
            }
        }
    }

    static func recentEntries() -> [String] {
        queue.sync { buffer }
    }
}
