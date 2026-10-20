// ZipArchive.swift — 精简 ZIP 读取（替代 ZIPFoundation 外部依赖）
//
// 为什么不用 ZIPFoundation：它需要通过 SwiftPM 从 GitHub 拉取，
// 在受限网络/沙箱环境下构建不可复现。这里用系统 Compression framework
// 直接解 raw DEFLATE，无任何第三方依赖。
//
// 支持：store(0) / deflate(8) 两种压缩方法，UTF-8 文件名，目录条目跳过。
// 不支持：ZIP64（>4GB）、加密、分卷。ROM 导入场景足够。
import Compression
import Foundation

struct ZipEntry {
    let path: String
    let data: Data
}

enum ZipError: LocalizedError {
    case notAZip
    case corrupt(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "不是有效的 zip 文件"
        case .corrupt(let reason): return "zip 结构损坏：\(reason)"
        case .unsupported(let reason): return "暂不支持：\(reason)"
        }
    }
}

enum ZipArchive {
    private static let eocdSignature: UInt32 = 0x0605_4B50
    private static let centralSignature: UInt32 = 0x0201_4B50
    private static let localSignature: UInt32 = 0x0403_4B50

    /// 解压全部文件条目（跳过目录）
    static func extract(url: URL) throws -> [ZipEntry] {
        let data = try Data(contentsOf: url)
        return try extract(data: data)
    }

    static func extract(data: Data) throws -> [ZipEntry] {
        guard data.count > 22 else { throw ZipError.notAZip }

        // 1. 从尾部回扫 EOCD（最多 64KB 注释）
        let maxScan = min(data.count, 65_557)
        var eocdOffset: Int?
        let scanStart = data.count - maxScan
        var i = data.count - 22
        while i >= scanStart {
            if try readUInt32(data, i) == eocdSignature {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdOffset else { throw ZipError.notAZip }

        let entryCount = Int(try readUInt16(data, eocd + 10))
        var cursor = Int(try readUInt32(data, eocd + 16))
        guard cursor >= 0, cursor < data.count else {
            throw ZipError.corrupt("中央目录偏移越界")
        }

        var results: [ZipEntry] = []
        results.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard try readUInt32(data, cursor) == centralSignature else {
                throw ZipError.corrupt("中央目录签名不匹配")
            }
            let flags = try readUInt16(data, cursor + 8)
            let method = try readUInt16(data, cursor + 10)
            let compressedSize = Int(try readUInt32(data, cursor + 20))
            let uncompressedSize = Int(try readUInt32(data, cursor + 24))
            let nameLen = Int(try readUInt16(data, cursor + 28))
            let extraLen = Int(try readUInt16(data, cursor + 30))
            let commentLen = Int(try readUInt16(data, cursor + 32))
            let localOffset = Int(try readUInt32(data, cursor + 42))

            guard cursor + 46 + nameLen <= data.count else {
                throw ZipError.corrupt("文件名越界")
            }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)

            cursor += 46 + nameLen + extraLen + commentLen

            // 跳过目录
            if name.hasSuffix("/") {
                continue
            }
            guard (flags & 0x1) == 0 else {
                throw ZipError.unsupported("加密条目 \(name)")
            }
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF,
                  localOffset != 0xFFFF_FFFF else {
                throw ZipError.unsupported("ZIP64（\(name)）")
            }

            // 2. 本地头定位数据起点
            guard localOffset + 30 <= data.count,
                  try readUInt32(data, localOffset) == localSignature else {
                throw ZipError.corrupt("本地头无效：\(name)")
            }
            let localNameLen = Int(try readUInt16(data, localOffset + 26))
            let localExtraLen = Int(try readUInt16(data, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compressedSize <= data.count else {
                throw ZipError.corrupt("数据越界：\(name)")
            }
            let payload = data.subdata(in: dataStart..<(dataStart + compressedSize))

            // 3. 解压
            let output: Data
            switch method {
            case 0: // store
                output = payload
            case 8: // deflate
                guard let inflated = inflateRaw(payload, expectedSize: uncompressedSize) else {
                    throw ZipError.corrupt("解压失败：\(name)")
                }
                output = inflated
            default:
                throw ZipError.unsupported("压缩方法 \(method)（\(name)）")
            }
            results.append(ZipEntry(path: name, data: output))
        }
        return results
    }

    // MARK: - raw DEFLATE 解压（Compression framework）

    private static func inflateRaw(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB 在 Apple API 中即 RFC1951 raw DEFLATE（zip 使用的格式）
                return compression_decode_buffer(
                    dstBase, expectedSize,
                    srcBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { return nil }
        return Data(output)
    }

    // MARK: - 小端读取

    private static func readUInt16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ZipError.corrupt("越界读 UInt16@\(offset)") }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private static func readUInt32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ZipError.corrupt("越界读 UInt32@\(offset)") }
        return data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}
