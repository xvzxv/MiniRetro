// CoreRegistryTests.swift — ROM 识别（XCTest 版，包装 C 层）
import XCTest
@testable import MiniRetro

final class CoreRegistryTests: XCTestCase {
    private func makeROM(_ configure: (inout [UInt8]) -> Void) -> [UInt8] {
        var rom = [UInt8](repeating: 0, count: 512)
        configure(&rom)
        return rom
    }

    func testINESMagic() {
        let rom = makeROM { rom in
            rom[0] = 0x4E; rom[1] = 0x45; rom[2] = 0x53; rom[3] = 0x1A
        }
        let match = rom.withUnsafeBufferPointer {
            mr_core_for_rom($0.baseAddress, $0.count)
        }
        XCTAssertEqual(String(cString: match.core_name!), "fceumm")
        XCTAssertEqual(String(cString: match.system_id!), "nes")
        XCTAssertTrue(match.by_magic)
    }

    func testGBCCMagic() {
        let rom = makeROM { rom in
            rom[0x104] = 0xCE; rom[0x105] = 0xED
            rom[0x106] = 0x66; rom[0x107] = 0x66
            rom[0x143] = 0x80
        }
        let match = rom.withUnsafeBufferPointer {
            mr_core_for_rom($0.baseAddress, $0.count)
        }
        XCTAssertEqual(String(cString: match.core_name!), "sameboy")
        XCTAssertEqual(String(cString: match.system_id!), "gbc")
    }

    func testGBAMagic() {
        let rom = makeROM { rom in
            rom[0xA0] = 0x24
            rom[0xB2] = 0x96
        }
        let match = rom.withUnsafeBufferPointer {
            mr_core_for_rom($0.baseAddress, $0.count)
        }
        XCTAssertEqual(String(cString: match.core_name!), "mgba")
        XCTAssertEqual(String(cString: match.system_id!), "gba")
    }

    func testUnknownData() {
        let rom = [UInt8](repeating: 0xAA, count: 512)
        let match = rom.withUnsafeBufferPointer {
            mr_core_for_rom($0.baseAddress, $0.count)
        }
        XCTAssertNil(match.core_name)
    }

    func testExtensionFallback() {
        let match = mr_core_for_extension("GBC")
        XCTAssertEqual(String(cString: match.core_name!), "sameboy")
        XCTAssertEqual(String(cString: match.system_id!), "gbc")
        XCTAssertFalse(match.by_magic)
    }
}
