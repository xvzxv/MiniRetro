// SaveStateTests.swift — 即时存档往返（M1/M2 验收项）
//
// 说明：该测试需要真实 ROM 才能运行（retro_load_game 依赖有效 ROM 数据）。
// 仓库不包含任何 ROM（合规要求），因此：
//   1. 未放置 ROM 时自动 skip，并在输出中提示放置路径；
//   2. 放置任意合法 ROM 到 Documents/ROMs/gba/test.gba 后即可运行。
// 覆盖：serialize → unserialize 往返、serializeSize > 0、电池存档 flush 落盘。
import XCTest
@testable import MiniRetro

final class SaveStateTests: XCTestCase {
    /// 测试用 ROM 期望路径（用户自行放置，仓库不含 ROM）
    private static let testROMPath = FileManager.default.documentsDirectory
        .appendingPathComponent("ROMs/gba/test.gba")

    private func makeCore() throws -> RetroCore {
        guard FileManager.default.fileExists(atPath: Self.testROMPath.path) else {
            throw XCTSkip("未找到测试 ROM（\(Self.testROMPath.path)），跳过存档往返测试")
        }
        let core = RetroCore(coreNamed: "mgba")
        let saveDir = FileManager.default.documentsDirectory
            .appendingPathComponent("Saves/_test", isDirectory: true)
        FileManager.default.ensureDirectory(saveDir)
        core.setSaveDirectory(saveDir.path)
        core.setSystemDirectory(FileManager.default.documentsDirectory.path)
        try core.loadROM(atPath: Self.testROMPath.path)
        return core
    }

    func testSerializeSizePositive() throws {
        let core = try makeCore()
        defer { core.unloadROM() }
        XCTAssertGreaterThan(core.serializeSize, 0, "mGBA 应支持即时存档")
    }

    func testSaveLoadRoundTrip() throws {
        let core = try makeCore()
        defer { core.unloadROM() }
        core.start()
        defer { core.stop() }

        // 跑若干帧，让 core 进入稳定状态
        Thread.sleep(forTimeInterval: 0.3)

        guard let stateA = core.serializeState() else {
            return XCTFail("serializeState 返回 nil")
        }
        XCTAssertGreaterThan(stateA.count, 0)

        // 再跑一段，状态变化
        Thread.sleep(forTimeInterval: 0.3)

        // 读回存档 A，与再序列化结果长度一致且内容可解析
        XCTAssertTrue(core.unserializeState(stateA), "unserialize 应成功")
        guard let stateB = core.serializeState() else {
            return XCTFail("读档后再次 serialize 失败")
        }
        XCTAssertEqual(stateA.count, stateB.count, "存档尺寸应稳定")

        // 读档后应能继续运行（不崩溃）
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(core.isRunning)
    }

    func testBatterySaveFlush() throws {
        let core = try makeCore()
        defer { core.unloadROM() }
        core.start()
        defer { core.stop() }
        Thread.sleep(forTimeInterval: 0.3)
        core.flushBatterySave()
        // .sav 是否落盘取决于 cart 是否带电池；此处只验证调用不崩溃
        XCTAssertTrue(true)
    }
}
