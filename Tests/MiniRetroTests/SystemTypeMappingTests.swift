// SystemTypeMappingTests.swift — 系统 ID 映射与 ROM 识别（防回归）
//
// 背景：曾出现真实缺陷 —— C 层 CoreRegistry 返回 "nes"，而 SystemType 的
// case 名是 fc（rawValue "fc"），`SystemType(rawValue:)` 直接返回 nil，
// 导致所有 .nes 文件导入时报「无法识别的格式」。
import XCTest
@testable import MiniRetro

final class SystemTypeMappingTests: XCTestCase {
    /// C 层可能返回的全部 system_id 都必须能映射到 SystemType
    func testEveryCoreRegistrySystemIDIsMappable() {
        let ids = ["nes", "fds", "unf", "unif", "gb", "gbc", "gba"]
        for id in ids {
            XCTAssertNotNil(
                SystemType.from(systemID: id),
                "system_id「\(id)」无法映射到 SystemType —— 会导致该格式全部导入失败"
            )
        }
    }

    func testExpectedMappings() {
        XCTAssertEqual(SystemType.from(systemID: "nes"), .fc)
        XCTAssertEqual(SystemType.from(systemID: "unf"), .fc)
        XCTAssertEqual(SystemType.from(systemID: "unif"), .fc)
        XCTAssertEqual(SystemType.from(systemID: "fds"), .fds)
        XCTAssertEqual(SystemType.from(systemID: "gb"), .gb)
        XCTAssertEqual(SystemType.from(systemID: "gbc"), .gbc)
        XCTAssertEqual(SystemType.from(systemID: "gba"), .gba)
        XCTAssertEqual(SystemType.from(systemID: "NES"), .fc, "应大小写不敏感")
        XCTAssertNil(SystemType.from(systemID: "n64"))
        XCTAssertNil(SystemType.from(systemID: ""))
    }

    /// 用户实际遇到的场景：中文名 + 方括号 + 括号的 .nes 文件，文件头非 iNES
    func testIdentifyFallsBackToExtensionForNES() {
        let payload = Data([0x00, 0x01, 0x02, 0x03] + [UInt8](repeating: 0, count: 256))
        let name = "水浒神兽[外星科技][CN][RPG](8Mb).nes"
        guard let result = ROMImporter.identify(data: payload, fileName: name) else {
            return XCTFail("扩展名兜底失败：.nes 文件必须能识别")
        }
        XCTAssertEqual(result.system, .fc)
        XCTAssertEqual(result.coreName, "fceumm")
        XCTAssertFalse(result.byMagic, "魔数不匹配时应标记为扩展名识别")
    }

    /// 真实 iNES 文件头应被魔数识别
    func testIdentifyNESByMagic() {
        var payload = Data([0x4E, 0x45, 0x53, 0x1A, 0x01, 0x01, 0x00, 0x00])
        payload.append(Data(repeating: 0, count: 16 * 1024 + 8 * 1024))
        guard let result = ROMImporter.identify(data: payload, fileName: "game.nes") else {
            return XCTFail("iNES 魔数识别失败")
        }
        XCTAssertEqual(result.system, .fc)
        XCTAssertTrue(result.byMagic)
    }

    /// UNIF 容器（早期汉化常见）
    func testIdentifyUNIF() {
        var payload = Data("UNIF".utf8)
        payload.append(Data(repeating: 0, count: 256))
        guard let result = ROMImporter.identify(data: payload, fileName: "hanhua.nes") else {
            return XCTFail("UNIF 魔数识别失败")
        }
        XCTAssertEqual(result.system, .fc)
        XCTAssertEqual(result.coreName, "fceumm")
        XCTAssertTrue(result.byMagic)
    }

    /// 未知扩展名 + 未知内容 → nil（走损坏分支）
    func testIdentifyUnknown() {
        let payload = Data(repeating: 0xAB, count: 512)
        XCTAssertNil(ROMImporter.identify(data: payload, fileName: "readme.txt"))
    }

    /// 空数据 + 已知扩展名 → 仍应按扩展名识别（避免误判为损坏）
    func testIdentifyEmptyDataWithKnownExtension() {
        let result = ROMImporter.identify(data: Data(), fileName: "empty.nes")
        XCTAssertEqual(result?.system, .fc)
        XCTAssertFalse(result?.byMagic ?? true)
    }
}
